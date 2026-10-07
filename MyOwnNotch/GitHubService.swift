//
//  GitHubService.swift
//  MyOwnNotch
//
//  Contribuições do GitHub. Lê o gráfico público de contribuições
//  (github.com/users/<user>/contributions), sem precisar de token.
//  Contribuições privadas só aparecem se "Private contributions" estiver
//  ativado no perfil do GitHub.
//

import Foundation
import Combine

struct GitHubDay: Identifiable, Equatable {
    var id: String { date }
    let date: String        // yyyy-MM-dd
    let count: Int
    let level: Int          // 0...4 (mesma escala de cores do GitHub)
}

@MainActor
final class GitHubService: ObservableObject {
    @Published var username: String
    @Published var days: [GitHubDay] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let defaultsKey = "githubUsername"
    private var poller: AnyCancellable?

    init() {
        username = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        poller = Timer.publish(every: 600, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    // MARK: - Derivados

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String { Self.dayFormatter.string(from: Date()) }

    var hasUsername: Bool { !username.isEmpty }

    var todayCount: Int { days.first(where: { $0.date == todayKey })?.count ?? 0 }

    /// Total do ano corrente (o que o GitHub mostra como "N contributions in 2026").
    var yearCount: Int {
        let year = String(todayKey.prefix(4))
        return days.filter { $0.date.hasPrefix(year) }.reduce(0) { $0 + $1.count }
    }

    var yearLabel: String { String(todayKey.prefix(4)) }

    /// Dias seguidos com contribuição. Se hoje ainda está zerado, a sequência de ontem continua valendo.
    var streak: Int {
        var list = days.filter { $0.date <= todayKey }
        if list.last?.date == todayKey, list.last?.count == 0 { list.removeLast() }
        var n = 0
        for d in list.reversed() { if d.count > 0 { n += 1 } else { break } }
        return n
    }

    // MARK: - Ações

    func setUsername(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        username = clean
        UserDefaults.standard.set(clean, forKey: defaultsKey)
        days = []
        errorMessage = nil
        refresh()
    }

    func refresh() {
        guard hasUsername,
              let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://github.com/users/\(encoded)/contributions") else { return }
        let requested = username
        isLoading = true
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let html = data.flatMap { String(data: $0, encoding: .utf8) }
            let parsed = html.map(Self.parse) ?? []
            DispatchQueue.main.async {
                guard let self, self.username == requested else { return }
                self.isLoading = false
                if status == 404 {
                    self.errorMessage = "Usuário não encontrado"
                } else if parsed.isEmpty {
                    self.errorMessage = "Sem conexão com o GitHub"
                } else {
                    self.errorMessage = nil
                    self.days = parsed
                }
            }
        }.resume()
    }

    // MARK: - Parse do HTML

    nonisolated private static func parse(_ html: String) -> [GitHubDay] {
        // <td ... data-date="2026-01-04" id="contribution-day-component-0-0" data-level="2" ...>
        guard let cellRe = try? NSRegularExpression(pattern: #"data-date="(\d{4}-\d{2}-\d{2})"\s+id="([^"]+)"\s+data-level="(\d)""#),
              // <tool-tip ... for="contribution-day-component-0-0" ...>16 contributions on January 4th.
              let tipRe = try? NSRegularExpression(pattern: #"for="(contribution-day-component-[^"]+)"[^>]*>\s*(No|\d+)\s+contributions?"#)
        else { return [] }

        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)

        var counts: [String: Int] = [:]
        for m in tipRe.matches(in: html, range: full) {
            let id = ns.substring(with: m.range(at: 1))
            let c = ns.substring(with: m.range(at: 2))
            counts[id] = c == "No" ? 0 : Int(c) ?? 0
        }

        var result: [GitHubDay] = []
        for m in cellRe.matches(in: html, range: full) {
            let date = ns.substring(with: m.range(at: 1))
            let id = ns.substring(with: m.range(at: 2))
            let level = Int(ns.substring(with: m.range(at: 3))) ?? 0
            result.append(GitHubDay(date: date, count: counts[id] ?? 0, level: level))
        }
        return result.sorted { $0.date < $1.date }
    }
}
