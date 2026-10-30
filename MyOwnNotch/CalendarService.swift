//
//  CalendarService.swift
//  MyOwnNotch
//
//  Próximos eventos via EventKit. Nada é iniciado no init; permissão só via requestAccess().
//

import AppKit
import EventKit
import Combine
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var nextEvent: CalendarEvent?
    @Published private(set) var upcoming: [CalendarEvent] = []
    @Published private(set) var authorization: LoadState = .idle

    private let store = EKEventStore()
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var running = false

    init() {}

    // MARK: - Ciclo de vida

    func start() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.calendarEnabled) else {
            stop()
            return
        }
        guard !running else { refresh(); return }
        running = true

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t

        refresh()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if let o = changeObserver {
            NotificationCenter.default.removeObserver(o)
            changeObserver = nil
        }
    }

    func requestAccess() {
        Task { @MainActor in
            do {
                let granted = try await store.requestFullAccessToEvents()
                authorization = granted ? .loaded : .noPermission
                if granted { refresh() }
            } catch {
                authorization = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Carregamento

    func refresh() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            setIfChanged(&authorization, .loaded)
        case .notDetermined:
            setIfChanged(&authorization, .idle)
            setIfChanged(&nextEvent, nil)
            setIfChanged(&upcoming, [])
            return
        case .denied, .restricted, .writeOnly:
            setIfChanged(&authorization, .noPermission)
            setIfChanged(&nextEvent, nil)
            setIfChanged(&upcoming, [])
            return
        @unknown default:
            setIfChanged(&authorization, .failed("Estado de autorização desconhecido"))
            return
        }

        let now = Date()
        let cal = Calendar.current
        let horizon = now.addingTimeInterval(12 * 3600)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? horizon

        // Janela cobre 12h à frente e o restante de hoje.
        let windowEnd = max(horizon, tomorrow)
        let predicate = store.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        setIfChanged(&nextEvent, events.first(where: { $0.startDate <= horizon }).map(Self.map))
        setIfChanged(&upcoming, events
            .filter { $0.startDate < tomorrow }
            .prefix(4)
            .map(Self.map))
    }

    private func setIfChanged<T: Equatable>(_ keyPath: inout T, _ value: T) {
        if keyPath != value { keyPath = value }
    }

    // MARK: - Mapeamento

    private static func map(_ e: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: (e.eventIdentifier ?? UUID().uuidString) + "-\(Int(e.startDate.timeIntervalSince1970))",
            title: (e.title?.isEmpty == false ? e.title! : "Sem título"),
            start: e.startDate,
            end: e.endDate,
            location: e.location?.isEmpty == false ? e.location : nil,
            joinURL: joinURL(for: e),
            colorHex: e.calendar.flatMap { hex(from: $0.cgColor) }
        )
    }

    private static let joinRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"https://[^\s<>"')]*?(meet\.google\.com|zoom\.us/j|teams\.microsoft\.com/l/meetup-join|facetime\.apple\.com|webex\.com)[^\s<>"')]*"#,
        options: [.caseInsensitive]
    )

    private static let allowedJoinHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com",
                                           "teams.live.com", "facetime.apple.com", "webex.com"]

    /// https, sem credenciais, host exato ou subdomínio (sufixo com ponto) de um provedor conhecido.
    static func validatedJoinURL(_ url: URL) -> URL? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.user == nil, c.password == nil,
              let host = c.host?.lowercased(), !host.isEmpty,
              allowedJoinHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }

    private static func joinURL(for e: EKEvent) -> URL? {
        if let u = e.url, let ok = validatedJoinURL(u) { return ok }
        for text in [e.notes, e.location] {
            guard let text, !text.isEmpty, let re = joinRegex else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for m in re.matches(in: text, range: range) {
                if let r = Range(m.range, in: text),
                   let url = URL(string: String(text[r])),
                   let ok = validatedJoinURL(url) {
                    return ok
                }
            }
        }
        return nil
    }

    private static func hex(from cg: CGColor) -> String? {
        guard let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
