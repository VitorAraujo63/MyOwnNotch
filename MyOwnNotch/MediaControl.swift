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

enum MediaRepeat { case off, all, one }

private let sep = "\u{1F}"   // separador que não aparece em títulos de músicas

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

        // Rede de segurança: ressincroniza a cada 3s (posição pode derivar)
        mediaPoller = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.fetchNowPlaying() }

        // Avança a barra de progresso localmente (suave, sem consultar o player)
        mediaTicker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.mediaIsPlaying, !self.isScrubbingMedia, self.mediaDuration > 0 else { return }
                self.mediaPosition = min(self.mediaDuration, self.mediaPosition + 0.5)
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.fetchNowPlaying() }
    }

    // MARK: - Leitura

    private static let mediaQueue = DispatchQueue(label: "notch.media", qos: .userInitiated)

    private static let nowPlayingScript = """
    set d to (ASCII character 31)
    if application "Spotify" is running then
        tell application "Spotify"
            if player state is not stopped then
                set t to current track
                return (name of t) & d & (artist of t) & d & (album of t) & d & (player state as string) & d & (artwork url of t) & d & "Spotify" & d & (duration of t) & d & ((player position * 1000) as integer) & d & (shuffling as string) & d & (repeating as string) & d & (id of t)
            end if
        end tell
    end if
    if application "Music" is running then
        tell application "Music"
            if player state is not stopped then
                set t to current track
                return (name of t) & d & (artist of t) & d & (album of t) & d & (player state as string) & d & "" & d & "Music" & d & ((duration of t * 1000) as integer) & d & ((player position * 1000) as integer) & d & (shuffle enabled as string) & d & (song repeat as string)
            end if
        end tell
    end if
    return "none"
    """

    func fetchNowPlaying() {
        Self.mediaQueue.async { [weak self] in
            var errorInfo: NSDictionary?
            let output = NSAppleScript(source: Self.nowPlayingScript)?
                .executeAndReturnError(&errorInfo).stringValue ?? "none"
            DispatchQueue.main.async { self?.applyNowPlaying(output) }
        }
    }

    private func applyNowPlaying(_ output: String) {
        let parts = output.components(separatedBy: sep)
        let wasPlaying = mediaIsPlaying
        let oldKey = lastMediaTrackKey

        guard parts.count >= 10, parts[3] == "playing" || parts[3] == "paused" else {
            mediaTitle = "Nenhuma mídia"; mediaArtist = ""; mediaAlbum = ""
            mediaIsPlaying = false; mediaSource = ""
            mediaDuration = 0; mediaPosition = 0
            currentArtUrl = ""; mediaArtwork = nil; lastMediaTrackKey = ""
            return
        }

        let title = parts[0].isEmpty ? "Desconhecido" : parts[0]
        let source = parts[5]
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
        mediaRepeat = source == "Spotify" ? (parts[9] == "true" ? .all : .off)
                                          : (parts[9] == "one" ? .one : (parts[9] == "all" ? .all : .off))
        lastMediaTrackKey = key
        let uri = parts.count > 10 ? parts[10] : ""
        if source == "Spotify", uri != mediaTrackURI {
            mediaTrackURI = uri
            spotify.trackChanged(uri: uri)
        }

        // Capa
        if source == "Spotify" {
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
        guard let urlObj = URL(string: url) else { return }
        URLSession.shared.dataTask(with: urlObj) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                // Só aplica se ainda for a faixa atual
                if self?.currentArtUrl == url { self?.mediaArtwork = image }
            }
        }.resume()
    }

    private func loadMusicArtwork() {
        let key = currentArtUrl
        Self.mediaQueue.async { [weak self] in
            let script = "tell application \"Music\" to get raw data of artwork 1 of current track"
            let data = NSAppleScript(source: script)?.executeAndReturnError(nil).data
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard self?.currentArtUrl == key else { return }
                self?.mediaArtwork = image
            }
        }
    }

    // MARK: - Comandos

    /// Executa um comando no player ativo (nunca abre o app se ele estiver fechado).
    private func tellPlayer(_ command: (String) -> String) {
        let apps = mediaSource.isEmpty ? ["Spotify", "Music"] : [mediaSource]
        let body = apps.map { app in "if application \"\(app)\" is running then\n tell application \"\(app)\"\n \(command(app))\n end tell\n return\nend if" }
            .joined(separator: "\n")
        Self.mediaQueue.async { [weak self] in
            NSAppleScript(source: body)?.executeAndReturnError(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.fetchNowPlaying() }
        }
    }

    func mediaPlayPause() {
        mediaIsPlaying.toggle()
        tellPlayer { _ in "playpause" }
    }

    /// Pula N faixas (usado ao clicar num item da fila)
    func mediaSkip(times: Int) {
        guard times > 0 else { return }
        tellPlayer { _ in "repeat \(times) times\n next track\n end repeat" }
    }

    func mediaNext() { tellPlayer { _ in "next track" } }

    func mediaPrevious() {
        // Como nos players: depois de 3s volta ao início da faixa, senão faixa anterior
        if mediaPosition > 3 { mediaSeek(to: 0) } else { tellPlayer { _ in "previous track" } }
    }

    func mediaSeek(to seconds: Double) {
        let target = max(0, min(seconds, max(mediaDuration - 1, 0)))
        mediaPosition = target
        tellPlayer { _ in "set player position to \(Int(target))" }
    }

    func mediaToggleShuffle() {
        mediaShuffle.toggle()
        tellPlayer { app in app == "Spotify" ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled" }
    }

    func mediaCycleRepeat() {
        switch mediaRepeat {
        case .off: mediaRepeat = .all
        case .all: mediaRepeat = mediaSource == "Music" ? .one : .off
        case .one: mediaRepeat = .off
        }
        let next = mediaRepeat
        tellPlayer { app in
            if app == "Spotify" { return "set repeating to \(next != .off)" }
            return "set song repeat to \(next == .one ? "one" : (next == .all ? "all" : "off"))"
        }
    }

    // MARK: Volume do player

    func fetchMediaVolume() {
        let app = mediaSource.isEmpty ? "Spotify" : mediaSource
        Self.mediaQueue.async { [weak self] in
            let script = "if application \"\(app)\" is running then tell application \"\(app)\" to return sound volume\nreturn -1"
            let v = NSAppleScript(source: script)?.executeAndReturnError(nil).int32Value ?? -1
            DispatchQueue.main.async { if v >= 0 { self?.mediaVolume = Double(v) } }
        }
    }

    func setMediaVolume(_ value: Double) {
        mediaVolume = value
        let v = Int(value)
        tellPlayer { _ in "set sound volume to \(v)" }
    }

    func openMediaApp(_ name: String? = nil) {
        let app = name ?? (mediaSource.isEmpty ? "Spotify" : mediaSource)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app == "Spotify" ? "com.spotify.client" : "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
