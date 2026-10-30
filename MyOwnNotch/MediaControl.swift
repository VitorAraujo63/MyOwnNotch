//
//  MediaControl.swift
//  MyOwnNotch
//
//  Conexão com Spotify e Apple Music: atualização instantânea via notificações do
//  sistema (sem esperar o polling), posição/duração, seek, shuffle e repeat.
//

import SwiftUI
import Combine
import AppKit
import ImageIO

enum MediaRepeat { case off, all, one }

private let sep = "\u{1F}"   // separador que não aparece em títulos de músicas

// MARK: - Players permitidos (whitelist)

/// Únicos players aceitos. Nomes e bundle IDs são constantes: nada vindo do player
/// (ou de `mediaSource`) é interpolado em AppleScript sem passar por aqui.
private enum MediaPlayer: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var expectedFields: Int { self == .spotify ? 11 : 10 }

    init?(source: String) { self.init(rawValue: source) }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Script de leitura: um por player, para um não quebrar o outro.
    var nowPlayingSource: String {
        switch self {
        case .spotify:
            return """
            set d to (ASCII character 31)
            tell application id "com.spotify.client"
                if player state is not stopped then
                    set t to current track
                    return (name of t) & d & (artist of t) & d & (album of t) & d & (player state as string) & d & (artwork url of t) & d & "Spotify" & d & (duration of t) & d & ((player position * 1000) as integer) & d & (shuffling as string) & d & (repeating as string) & d & (id of t)
                end if
            end tell
            return "none"
            """
        case .music:
            return """
            set d to (ASCII character 31)
            tell application id "com.apple.Music"
                if player state is not stopped then
                    set t to current track
                    return (name of t) & d & (artist of t) & d & (album of t) & d & (player state as string) & d & "" & d & "Music" & d & ((duration of t * 1000) as integer) & d & ((player position * 1000) as integer) & d & (shuffle enabled as string) & d & (song repeat as string)
                end if
            end tell
            return "none"
            """
        }
    }
}

/// Executa e cacheia NSAppleScript. Tudo roda na fila serial `queue`; por isso o cache
/// mutável é seguro (`@unchecked Sendable`) e fica fora do MainActor.
private final class MediaScriptRunner: @unchecked Sendable {
    static let shared = MediaScriptRunner()
    let queue = DispatchQueue(label: "notch.media", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    struct Result: Sendable {
        var string: String?
        var data: Data?
        var int: Int32?
        var errorNumber: Int?
    }

    /// Chamar apenas dentro de `queue`.
    func run(_ source: String, cached: Bool) -> Result {
        let script: NSAppleScript?
        if cached, let hit = cache[source] { script = hit }
        else {
            script = NSAppleScript(source: source)
            if cached, let script { cache[source] = script }
        }
        guard let script else { return Result() }
        var info: NSDictionary?
        let d = script.executeAndReturnError(&info)
        var r = Result()
        if let info { r.errorNumber = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1; return r }
        r.string = d.stringValue
        r.data = d.data
        r.int = d.int32Value
        return r
    }
}

private let appleEventsDeniedCode = -1743

private func downsampledImage(from data: Data, maxPixel: Int = 160) -> NSImage? {
    let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let src = CGImageSourceCreateWithData(data as CFData, opts as CFDictionary) else { return nil }
    let thumbOpts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

extension NotchViewModel {

    // MARK: - Início

    func startMediaPolling() {
        // Spotify e Music avisam o sistema a cada play/pause/troca de faixa
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            center.publisher(for: Notification.Name(name))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.fetchNowPlaying() }
                }
                .store(in: &mediaCancellables)
        }

        // Abrir/fechar Spotify ou Music: busca imediata (e limpa o estado ao fechar)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard let id = app?.bundleIdentifier, MediaPlayer.allCases.contains(where: { $0.bundleID == id }) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.fetchNowPlaying() }
                }
                .store(in: &mediaCancellables)
        }

        // Rede de segurança com intervalo longo: ignora ticks com o Mac dormindo e,
        // sem nenhum player aberto, fetchNowPlaying não executa AppleScript.
        let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSystemAsleep else { return }
                self.fetchNowPlaying()
            }
        }
        timer.tolerance = 5.0
        RunLoop.main.add(timer, forMode: .common)
        mediaPoller = AnyCancellable { timer.invalidate() }

        updateMediaTickerForVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.fetchNowPlaying() }
    }

    // MARK: - Ticker de posição (só com a aba de mídia visível)

    /// Chamar quando `state` ou `activeModule` mudarem.
    func updateMediaTickerForVisibility() {
        if state == .expanded && activeModule == .media { startMediaTicker() } else { stopMediaTicker() }
    }

    private func startMediaTicker() {
        guard mediaTicker == nil else { return }
        // Avança a barra de progresso localmente (suave, sem consultar o player)
        mediaTicker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.mediaIsPlaying, !self.isScrubbingMedia, self.mediaDuration > 0 else { return }
                self.mediaPosition = min(self.mediaDuration, self.mediaPosition + 0.5)
            }
        fetchNowPlaying()   // ressincroniza a posição ao abrir a aba
    }

    private func stopMediaTicker() {
        mediaTicker?.cancel()
        mediaTicker = nil
    }

    // MARK: - Leitura

    func fetchNowPlaying() {
        let running = MediaPlayer.allCases.filter { $0.isRunning }
        guard !running.isEmpty else { applyNowPlaying("none", errorNumber: nil); return }
        let sources = running.map(\.nowPlayingSource)
        let runner = MediaScriptRunner.shared
        runner.queue.async { [weak self] in
            var output = "none"
            var errorNumber: Int?
            for src in sources {
                let r = runner.run(src, cached: true)
                if let e = r.errorNumber { errorNumber = e; continue }
                if let s = r.string, s != "none" { output = s; errorNumber = nil; break }
            }
            DispatchQueue.main.async { self?.applyNowPlaying(output, errorNumber: errorNumber) }
        }
    }

    private func applyNowPlaying(_ output: String, errorNumber: Int?) {
        if errorNumber == appleEventsDeniedCode { automationDenied = true }
        else if errorNumber == nil { automationDenied = false }

        let parts = output.components(separatedBy: sep)
        let wasPlaying = mediaIsPlaying
        let oldKey = lastMediaTrackKey

        guard parts.count >= 6, let player = MediaPlayer(source: parts[5]), parts.count == player.expectedFields,
              parts[3] == "playing" || parts[3] == "paused" else {
            mediaTitle = "Nenhuma mídia"; mediaArtist = ""; mediaAlbum = ""
            mediaIsPlaying = false; mediaSource = ""
            mediaDuration = 0; mediaPosition = 0
            currentArtUrl = ""; mediaArtwork = nil; lastMediaTrackKey = ""
            return
        }

        let title = parts[0].isEmpty ? "Desconhecido" : parts[0]
        let source = player.rawValue   // só "Spotify" ou "Music"
        let playing = parts[3] == "playing"
        let key = "\(source)|\(title)|\(parts[1])"

        mediaTitle = title
        mediaArtist = parts[1]
        mediaAlbum = parts[2]
        mediaSource = source
        mediaIsPlaying = playing
        mediaDuration = (Double(parts[6]) ?? 0) / 1000
        if !isScrubbingMedia { mediaPosition = (Double(parts[7]) ?? 0) / 1000 }
        mediaShuffle = parts[8] == "true"
        mediaRepeat = player == .spotify ? (parts[9] == "true" ? .all : .off)
                                         : (parts[9] == "one" ? .one : (parts[9] == "all" ? .all : .off))
        lastMediaTrackKey = key
        if player == .spotify {
            let uri = parts[10]
            if uri != mediaTrackURI {
                mediaTrackURI = uri
                spotify.trackChanged(uri: uri)
            }
        }

        // Capa
        if player == .spotify {
            let url = parts[4]
            if !url.isEmpty && url != currentArtUrl { currentArtUrl = url; loadArtwork(url: url) }
        } else if key != oldKey {
            currentArtUrl = "music:\(key)"
            loadMusicArtwork()
        }

        // Aviso compacto ao trocar de faixa / dar play com o notch recolhido
        if state == .idle {
            if !oldKey.isEmpty && key != oldKey { showCompact(module: .media, duration: 4.0) }
            else if playing && !wasPlaying { showCompact(module: .media, duration: 3.0) }
        }
    }

    private func loadArtwork(url: String) {
        // Só https (a URL vem do player; evita file://, http:// e afins)
        guard let urlObj = URL(string: url), urlObj.scheme?.lowercased() == "https" else { return }
        URLSession.shared.dataTask(with: urlObj) { [weak self] data, _, _ in
            guard let data, let image = downsampledImage(from: data) else { return }
            DispatchQueue.main.async {
                // Só aplica se ainda for a faixa atual
                if self?.currentArtUrl == url { self?.mediaArtwork = image }
            }
        }.resume()
    }

    private func loadMusicArtwork() {
        guard MediaPlayer.music.isRunning else { return }
        let key = currentArtUrl
        let runner = MediaScriptRunner.shared
        runner.queue.async { [weak self] in
            let script = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            let data = runner.run(script, cached: true).data
            let image = data.flatMap { downsampledImage(from: $0) }
            DispatchQueue.main.async {
                guard self?.currentArtUrl == key else { return }
                self?.mediaArtwork = image
            }
        }
    }

    // MARK: - Comandos

    /// Executa um comando nos players (nunca abre o app se ele estiver fechado).
    /// Só players da whitelist e em execução; `command` recebe apenas o enum interno.
    private func tellPlayer(_ command: (MediaPlayerKind) -> String) {
        let candidates: [MediaPlayer] = MediaPlayer(source: mediaSource).map { [$0] } ?? MediaPlayer.allCases
        let blocks = candidates.filter { $0.isRunning }.map { p in
            "tell application id \"\(p.bundleID)\"\n \(command(p == .spotify ? .spotify : .music))\n end tell"
        }
        guard !blocks.isEmpty else { return }
        let body = blocks.joined(separator: "\n")
        let runner = MediaScriptRunner.shared
        runner.queue.async { [weak self] in
            let r = runner.run(body, cached: false)
            let denied = r.errorNumber == appleEventsDeniedCode
            DispatchQueue.main.async {
                if denied { self?.automationDenied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.fetchNowPlaying() }
            }
        }
    }

    func mediaPlayPause() {
        mediaIsPlaying.toggle()
        tellPlayer { _ in "playpause" }
    }

    /// Pula N faixas (usado ao clicar num item da fila)
    func mediaSkip(times: Int) {
        let n = min(max(times, 0), 50)
        guard n > 0 else { return }
        tellPlayer { _ in "repeat \(n) times\n next track\n end repeat" }
    }

    func mediaNext() { tellPlayer { _ in "next track" } }

    func mediaPrevious() {
        // Como nos players: depois de 3s volta ao início da faixa, senão faixa anterior
        if mediaPosition > 3 { mediaSeek(to: 0) } else { tellPlayer { _ in "previous track" } }
    }

    func mediaSeek(to seconds: Double) {
        let target = max(0, min(seconds, max(mediaDuration - 1, 0)))
        mediaPosition = target
        let t = Int(target)
        tellPlayer { _ in "set player position to \(t)" }
    }

    func mediaToggleShuffle() {
        mediaShuffle.toggle()
        tellPlayer { app in app == .spotify ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled" }
    }

    func mediaCycleRepeat() {
        switch mediaRepeat {
        case .off: mediaRepeat = .all
        case .all: mediaRepeat = mediaSource == "Music" ? .one : .off
        case .one: mediaRepeat = .off
        }
        let next = mediaRepeat
        tellPlayer { app in
            if app == .spotify { return "set repeating to \(next != .off)" }
            return "set song repeat to \(next == .one ? "one" : (next == .all ? "all" : "off"))"
        }
    }

    // MARK: Volume do player

    func fetchMediaVolume() {
        let player = MediaPlayer(source: mediaSource) ?? .spotify
        guard player.isRunning else { return }
        let runner = MediaScriptRunner.shared
        runner.queue.async { [weak self] in
            let script = "tell application id \"\(player.bundleID)\" to return sound volume"
            let v = runner.run(script, cached: true).int ?? -1
            DispatchQueue.main.async { if v >= 0 { self?.mediaVolume = Double(v) } }
        }
    }

    func setMediaVolume(_ value: Double) {
        mediaVolume = value
        let v = min(max(Int(value), 0), 100)
        tellPlayer { _ in "set sound volume to \(v)" }
    }

    func openMediaApp(_ name: String? = nil) {
        let player = MediaPlayer(source: name ?? mediaSource) ?? .spotify
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private enum MediaPlayerKind { case spotify, music }
