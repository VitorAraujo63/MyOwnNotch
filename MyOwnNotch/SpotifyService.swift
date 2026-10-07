//
//  SpotifyService.swift
//  MyOwnNotch
//
//  Conexão OAuth (PKCE) com a Web API do Spotify: fila "Playing Next" e curtir faixa.
//  O login abre o navegador; o retorno é recebido por um servidor local em 127.0.0.1.
//  Tokens ficam no Keychain. O Client ID é o de um app do próprio usuário.
//

import SwiftUI
import Network
import Combine
import CryptoKit
import Security

struct SpotifyQueueItem: Identifiable, Equatable {
    let id: String          // uri
    let name: String
    let artist: String
    let artworkURL: URL?
}

struct SpotifyDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool
    var isThisMac: Bool { type == "Computer" && (Host.current().localizedName.map { name.contains($0) || $0.contains(name) } ?? false) }
    var icon: String {
        switch type {
        case "Computer": return "laptopcomputer"
        case "Smartphone": return "iphone"
        case "Tablet": return "ipad"
        case "TV", "CastVideo": return "tv"
        case "Speaker", "CastAudio", "AVR", "STB", "AudioDongle": return "hifispeaker.fill"
        case "GameConsole": return "gamecontroller.fill"
        case "Automobile": return "car.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}

@MainActor
final class SpotifyService: ObservableObject {

    static let redirectPort: UInt16 = 8765
    static let redirectURI = "http://127.0.0.1:8765/callback"
    private static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-library-modify"

    @Published var clientID: String = UserDefaults.standard.string(forKey: "spotifyClientId") ?? "" {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyClientId") }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var queue: [SpotifyQueueItem] = []
    @Published private(set) var isLiked = false
    @Published private(set) var devices: [SpotifyDevice] = []
    /// Último erro da API (ex.: Premium exigido); exibido nos painéis da fila e dos dispositivos
    @Published private(set) var apiError: String?
    private var lastTrackURI = ""

    private var accessToken: String?
    private var refreshToken: String?
    private var expiry: Date = .distantPast
    private var listener: NWListener?
    private var codeVerifier = ""
    private var oauthState = ""
    private var currentTrackID = ""

    init() {
        accessToken = Keychain.get("access")
        refreshToken = Keychain.get("refresh")
        if let e = Keychain.get("expiry"), let t = TimeInterval(e) { expiry = Date(timeIntervalSince1970: t) }
        isConnected = refreshToken != nil
    }

    private var cleanClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Login (PKCE)

    func connect() {
        guard !cleanClientID.isEmpty else { errorMessage = "Cole o Client ID do seu app Spotify."; return }
        errorMessage = nil
        isConnecting = true
        stopListener()

        codeVerifier = Self.randomString(64)
        oauthState = Self.randomString(16)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(codeVerifier.utf8))))

        do { try startListener() } catch {
            fail("Porta \(Self.redirectPort) ocupada. Feche o que estiver usando e tente de novo.")
            return
        }

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: cleanClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: oauthState),
        ]
        NSWorkspace.shared.open(c.url!)

        // Desiste se o usuário não concluir em 3 minutos
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            if self?.isConnecting == true { self?.fail("Tempo esgotado. Tente conectar novamente.") }
        }
    }

    func disconnect() {
        Keychain.delete("access"); Keychain.delete("refresh"); Keychain.delete("expiry")
        accessToken = nil; refreshToken = nil; expiry = .distantPast
        isConnected = false; queue = []; isLiked = false; devices = []; apiError = nil
    }

    private func fail(_ message: String) {
        stopListener()
        isConnecting = false
        errorMessage = message
    }

    // MARK: Servidor local de retorno

    private func startListener() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.redirectPort)!)
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let line = request.components(separatedBy: "\r\n").first ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let ok = path.hasPrefix("/callback")
                let body = "<html><head><meta charset='utf-8'><title>MyOwnNotch</title></head><body style='font-family:-apple-system;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0'><div style='text-align:center'><h2>\(ok ? "Conectado ✓" : "Ok")</h2><p style='color:#888'>Você já pode fechar esta aba e voltar ao notch.</p></div></body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                if ok { Task { @MainActor in await self?.handleCallback(path: path) } }
            }
        }
        l.start(queue: .main)
        listener = l
    }

    private func stopListener() { listener?.cancel(); listener = nil }

    private func handleCallback(path: String) async {
        guard let comps = URLComponents(string: "http://127.0.0.1" + path) else { return }
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        stopListener()
        if let err = items["error"] { fail(err == "access_denied" ? "Acesso negado no Spotify." : "Erro do Spotify: \(err)"); return }
        guard items["state"] == oauthState, let code = items["code"] else { fail("Resposta inválida do Spotify."); return }

        let ok = await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "client_id": cleanClientID, "code_verifier": codeVerifier,
        ])
        isConnecting = false
        if ok { isConnected = true; errorMessage = nil; apiError = nil; trackChanged(uri: lastTrackURI) }
        else if errorMessage == nil { errorMessage = "Não foi possível concluir o login." }
    }

    // MARK: Tokens

    @discardableResult
    private func tokenRequest(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(Self.formEscape($0.value))" }.joined(separator: "&").data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Sem conexão com o Spotify."; return false
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let token = json["access_token"] as? String else {
            let desc = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "erro"
            errorMessage = desc == "invalid_client" ? "Client ID inválido." : "Spotify: \(desc)"
            if (json["error"] as? String) == "invalid_grant" { disconnect() }
            return false
        }
        accessToken = token
        if let r = json["refresh_token"] as? String { refreshToken = r; Keychain.set("refresh", r) }
        expiry = Date().addingTimeInterval((json["expires_in"] as? TimeInterval ?? 3600) - 60)
        Keychain.set("access", token); Keychain.set("expiry", String(expiry.timeIntervalSince1970))
        return true
    }

    private func validToken() async -> String? {
        if let t = accessToken, expiry > Date() { return t }
        guard let r = refreshToken else { return nil }
        let ok = await tokenRequest(["grant_type": "refresh_token", "refresh_token": r, "client_id": cleanClientID])
        return ok ? accessToken : nil
    }

    // MARK: - API

    private func api(_ method: String, _ path: String, query: [String: String] = [:], json: [String: Any]? = nil) async -> (Int, Data)? {
        guard isConnected, let token = await validToken() else { return nil }
        var c = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401 { expiry = .distantPast }   // força refresh na próxima chamada
        if status == 403 {
            // O corpo pode ser JSON {"error":{"message":…}} ou texto puro
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            let msg = (json?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            if msg.lowercased().contains("premium") {
                apiError = "O Spotify exige Premium na conta dona do app (a que criou o Client ID). Use o Client ID de um app criado por uma conta Premium e adicione a sua conta em User Management."
            } else if msg.lowercased().contains("registered") {
                apiError = "Sua conta não está autorizada neste app. Adicione-a em User Management no painel do Spotify."
            } else if !msg.isEmpty {
                apiError = "Spotify: \(msg)"
            }
        } else if (200..<300).contains(status) {
            apiError = nil
        }
        return (status, data)
    }

    func refreshQueue() async {
        guard let (status, data) = await api("GET", "/me/player/queue"), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["queue"] as? [[String: Any]] else { return }
        var seen = Set<String>()
        queue = items.compactMap { t in
            guard let uri = t["uri"] as? String, let name = t["name"] as? String else { return nil }
            let artist = ((t["artists"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
            let images = (t["album"] as? [String: Any])?["images"] as? [[String: Any]]
            // menor imagem ≥ 64px costuma ser a penúltima
            let img = (images?.dropLast().last ?? images?.last)?["url"] as? String
            return SpotifyQueueItem(id: uri, name: name, artist: artist, artworkURL: img.flatMap(URL.init))
        }
        .filter { seen.insert($0.id).inserted }
        .prefix(8).map { $0 }
    }

    /// Chamado quando a faixa muda (URI vem do AppleScript: spotify:track:ID)
    func trackChanged(uri: String) {
        lastTrackURI = uri
        guard isConnected else { return }
        let id = uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : ""
        currentTrackID = id
        isLiked = false
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)   // dá tempo da fila atualizar no Spotify
            await refreshQueue()
            await refreshLiked()
        }
    }

    private func refreshLiked() async {
        guard !currentTrackID.isEmpty,
              let (status, data) = await api("GET", "/me/tracks/contains", query: ["ids": currentTrackID]), status == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Bool] else { return }
        isLiked = arr.first ?? false
    }

    func toggleLike() {
        guard !currentTrackID.isEmpty else { return }
        let target = !isLiked
        isLiked = target   // otimista
        let id = currentTrackID
        Task {
            let r = await api(target ? "PUT" : "DELETE", "/me/tracks", query: ["ids": id])
            if r == nil || !(200..<300).contains(r!.0) { isLiked = !target }
        }
    }

    // MARK: Dispositivos (Spotify Connect)

    func refreshDevices() async {
        guard let (status, data) = await api("GET", "/me/player/devices"), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["devices"] as? [[String: Any]] else { return }
        devices = arr.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return SpotifyDevice(id: id, name: name, type: d["type"] as? String ?? "",
                                 isActive: d["is_active"] as? Bool ?? false)
        }
    }

    /// Transfere a reprodução para outro dispositivo, mantendo o estado (tocando/pausado).
    func transfer(to device: SpotifyDevice) {
        devices = devices.map { SpotifyDevice(id: $0.id, name: $0.name, type: $0.type, isActive: $0.id == device.id) }
        Task {
            _ = await api("PUT", "/me/player", json: ["device_ids": [device.id], "play": true])
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshDevices()
        }
    }

    // MARK: Utilidades

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
    private static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func formEscape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? s
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "treenity.MyOwnNotch.spotify"

    static func set(_ account: String, _ value: String) {
        delete(account)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
