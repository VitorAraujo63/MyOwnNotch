//
//  NotchViewModel.swift
//  MyOwnNotch
//
//  Estado central do Notch. Controla qual módulo está ativo,
//  o estado de expansão, e propaga dados dos módulos.
//

import SwiftUI
import Combine
import IOKit.ps
import UserNotifications
import os
import Foundation

// MARK: - Estado do Notch

enum NotchState: Equatable {
    case idle
    case compact
    case expanded
}

// MARK: - Módulo Ativo

enum TimerMode: String, CaseIterable {
    case focus = "Focus", rest = "Break"
}

enum NotchModule: Equatable, Hashable {
    case none
    case media
    case battery
    case timer
    case systemMonitor
    case weather
    case actions
    case volume
    case terminal
    case crypto
    case tray
    case agent
    case github
    case calendar
    case clipboard

    /// Módulos que o usuário pode ocultar/exibir (exclui `.none` e o HUD de volume).
    static let userModules: [NotchModule] = [
        .media, .battery, .timer, .systemMonitor, .weather, .actions,
        .crypto, .tray, .terminal, .agent, .github, .calendar, .clipboard
    ]
}

// MARK: - CryptoCoin Struct

struct CryptoCoin {
    var symbol: String
    var name: String
    var price: String
    var change: String
    var isPositive: Bool
    var points: [CGFloat]
}

struct WeatherDay: Identifiable {
    let id: String          // data ISO (yyyy-MM-dd) ou índice — único
    let label: String
    let icon: String
    let high: String
    let low: String
}

/// Resultado do parse do JSON do wttr.in (valores já formatados para a UI).
struct ParsedWeather {
    var temp: String
    var desc: String
    var icon: String
    var feelsLike: String
    var humidity: String
    var wind: String
    var high: String
    var low: String
    var isDay: Bool
    var locationName: String
    var forecast: [WeatherDay]
}

// MARK: - ViewModel


@MainActor
class NotchViewModel: ObservableObject {

    // Estado visual (mudanças reavaliam quais pollers precisam rodar)
    @Published var state: NotchState = .idle {
        didSet { if oldValue != state { updatePollingForVisibility() } }
    }
    @Published var activeModule: NotchModule = .none {
        didSet { if oldValue != activeModule { updatePollingForVisibility() } }
    }
    @Published var isVisible: Bool = true
    @Published var isHovered: Bool = false
    @Published var metrics: NotchMetrics = NotchMetrics.measure(NotchMetrics.preferredScreen())

    var islandSize: CGSize {
        metrics.islandSize(for: state, hasActivity: hasLiveActivity, module: activeModule)
    }

    /// Há alguma Live Activity ocupando as asas do notch no estado idle.
    var hasLiveActivity: Bool { !liveActivities.isEmpty }

    /// Este Mac tem bateria interna? (calculado uma vez)
    let hasBattery: Bool = NotchViewModel.detectBattery()

    private static func detectBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains { source in
            let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            return (info?[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType
        }
    }

    // Contrato com outros serviços
    /// Setado pelo MediaControl / ações quando o macOS nega automação (erro -1743).
    @Published var automationDenied: Bool = false
    @Published var weatherStatus: LoadState = .idle
    @Published var cryptoStatus: LoadState = .idle

    // Módulo de Mídia
    @Published var mediaTitle: String = "Nenhuma mídia"
    @Published var mediaArtist: String = ""
    @Published var mediaIsPlaying: Bool = false {
        didSet {
            guard oldValue != mediaIsPlaying else { return }
            updateAudioBarsForVisibility()
            recomputeLiveActivities()
        }
    }
    @Published var mediaArtwork: NSImage? = nil
    @Published var audioBars: [CGFloat] = Array(repeating: 0.2, count: 5)

    // Estado detalhado do player (Spotify / Apple Music)
    @Published var mediaAlbum: String = ""
    @Published var mediaDuration: Double = 0        // segundos
    @Published var mediaPosition: Double = 0        // segundos
    @Published var mediaShuffle: Bool = false
    @Published var mediaRepeat: MediaRepeat = .off
    @Published var mediaSource: String = ""         // "Spotify", "Music" ou "" (nenhum player ativo)
    @Published var mediaVolume: Double = 50         // volume do player (0–100)
    var isScrubbingMedia = false
    var currentArtUrl: String = ""
    var mediaCancellables = Set<AnyCancellable>()
    var lastMediaTrackKey = ""

    // Módulo de Bateria
    @Published var batteryLevel: Int = 100 {
        didSet { if oldValue != batteryLevel { recomputeLiveActivities() } }
    }
    @Published var batteryIsCharging: Bool = false {
        didSet { if oldValue != batteryIsCharging { recomputeLiveActivities() } }
    }
    @Published var batteryDetails = BatteryDetails()

    // Módulo de Timer
    @Published var timerSeconds: Int = 25 * 60 {
        didSet { if oldValue != timerSeconds { recomputeLiveActivities() } }
    }
    @Published var timerIsRunning: Bool = false {
        didSet { if oldValue != timerIsRunning { recomputeLiveActivities() } }
    }
    @Published var timerPresetMinutes: Int = 25
    @Published var timerMode: TimerMode = .focus
    @Published var timerSoundEnabled: Bool = true {
        didSet { if oldValue != timerSoundEnabled { UserDefaults.standard.set(timerSoundEnabled, forKey: SettingsKey.timerSoundEnabled) } }
    }
    var timerFocusMinutes = 25 {
        didSet { if oldValue != timerFocusMinutes { UserDefaults.standard.set(timerFocusMinutes, forKey: SettingsKey.timerFocusMinutes) } }
    }
    var timerBreakMinutes = 5 {
        didSet { if oldValue != timerBreakMinutes { UserDefaults.standard.set(timerBreakMinutes, forKey: SettingsKey.timerBreakMinutes) } }
    }
    /// Tempo no valor inicial (régua ativa) — ainda não começou / foi reiniciado
    var timerIsIdle: Bool { !timerIsRunning && timerSeconds == timerPresetMinutes * 60 }

    // Novos Módulos: Sistema, Clima, Volume
    @Published var cpuUsage: Double = 0.0
    @Published var gpuUsage: Double = 0.0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 24)
    @Published var gpuHistory: [Double] = Array(repeating: 0, count: 24)
    @Published var ramHistory: [Double] = Array(repeating: 0, count: 24)
    @Published var ramUsage: Double = 0.0
    private var previousCpuInfo: processor_info_array_t?
    private var previousCpuInfoCount: mach_msg_type_number_t = 0
    private var isFetchingSystemStats = false

    @Published var weatherTemp: String = "--°C"
    @Published var weatherDesc: String = "Buscando..."
    @Published var weatherIcon: String = "thermometer"
    @Published var weatherFeelsLike: String = "--°"
    @Published var weatherHumidity: String = "--%"
    @Published var weatherWind: String = "-- km/h"
    @Published var weatherHigh: String = "--°"
    @Published var weatherLow: String = "--°"
    @Published var weatherIsDay: Bool = true
    @Published var weatherLocationDisplay: String = "Local..."
    @Published var weatherSearchInput: String = ""
    @Published var weatherForecast: [WeatherDay] = []
    /// Local salvo ("" = automático). Persistido em SettingsKey.weatherLocation.
    private(set) var weatherLocation: String = ""

    @Published var cryptoCoins: [CryptoCoin] = [
        CryptoCoin(symbol: "BTC", name: "Bitcoin", price: "...", change: "0", isPositive: true, points: [1,1,1]),
        CryptoCoin(symbol: "USD", name: "Dólar", price: "...", change: "0", isPositive: true, points: [1,1,1]),
        CryptoCoin(symbol: "EUR", name: "Euro", price: "...", change: "0", isPositive: true, points: [1,1,1])
    ]

    // Volume do sistema (CoreAudio, orientado a eventos)
    @Published var systemVolume: Double = 0.5      // 0–1
    @Published var systemMuted: Bool = false
    /// Compatibilidade com as views: 0–100 (0 quando mudo).
    var currentVolume: Int { systemMuted ? 0 : Int((systemVolume * 100).rounded()) }
    private let audioVolume = SystemAudioVolume()

    // Terminal
    let terminal = TerminalSession()
    let agent = AgentSession()
    let spotify = SpotifyService()
    let github = GitHubService()
    var mediaTrackURI = ""

    // Calendário e privacidade (views observam diretamente)
    let calendar = CalendarService()
    let privacy = PrivacyMonitor()

    // Clipboard
    let clipboard = ClipboardService()

    // Toggles de sistema
    private let stayAwakeAssertion = StayAwakeAssertion()
    private let capsLockMonitor = CapsLockMonitor()
    /// "Manter acordado" (IOPMAssertion). Não persistido: sempre desligado ao abrir o app.
    @Published var stayAwake: Bool = false {
        didSet {
            guard oldValue != stayAwake else { return }
            if stayAwake {
                if !stayAwakeAssertion.acquire() { stayAwake = false; return }
            } else {
                stayAwakeAssertion.release()
            }
            recomputeLiveActivities()
        }
    }
    @Published private(set) var capsLockOn: Bool = false {
        didSet { if oldValue != capsLockOn { recomputeLiveActivities() } }
    }
    @Published private(set) var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    // Aparência (gravada pela tela de Ajustes via @AppStorage)
    @Published var surfaceStyle: SurfaceStyle = .dynamicGlass
    @Published var accentChoice: AccentChoice = .module
    @Published var solidOnLowPower: Bool = true
    var effectiveSurfaceStyle: SurfaceStyle { (solidOnLowPower && isLowPowerMode) ? .black : surfaceStyle }
    var swipeToSkipTrack: Bool { defaults.object(forKey: SettingsKey.swipeToSkipTrack) as? Bool ?? true }

    func toggleStayAwake() { stayAwake.toggle() }

    // Live activities
    @Published private(set) var liveActivities: [LiveActivity] = []
    var primaryLiveActivity: LiveActivity? { liveActivities.first }
    var secondaryLiveActivity: LiveActivity? { liveActivities.dropFirst().first }

    // Módulos ocultos
    @Published var hiddenModules: Set<NotchModule> = [] {
        didSet { if oldValue != hiddenModules { saveHiddenModules() } }
    }
    var visibleModules: [NotchModule] { NotchModule.userModules.filter { !hiddenModules.contains($0) } }
    func isModuleVisible(_ module: NotchModule) -> Bool { !hiddenModules.contains(module) }

    // Bandeja de arquivos
    @Published var trayItems: [TrayItem] = []
    @Published var isDropTargeted: Bool = false
    @Published private(set) var trayIsZipping: Bool = false
    /// Mensagem do último erro ao compactar (nil = sem erro).
    @Published private(set) var trayZipError: String?
    private let trayDefaultsKey = "trayPaths"

    // Timers
    private var timerCancellable: AnyCancellable?
    private var timerEndDate: Date?
    private var audioBarsTimer: Timer?
    var mediaPoller: AnyCancellable?
    var mediaTicker: AnyCancellable?
    private var systemTimer: Timer?
    private var cryptoTimer: Timer?
    private var weatherTimer: Timer?
    private var meetingTimer: Timer?
    private var compactTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var cryptoTask: Task<Void, Never>?

    private var lastWeatherFetch: Date?
    private var lastCryptoFetch: Date?
    private var shownModule: NotchModule = .none
    /// Verdadeiro entre willSleep/screensDidSleep e didWake/screensDidWake.
    /// Outros serviços (ex.: MediaControl) podem consultar para pausar seus timers.
    private(set) var isSystemAsleep = false
    private var sleepReasons = 0

    private let powerMonitor = PowerMonitor()
    private var cancellables = Set<AnyCancellable>()

    // Módulo de Armazenamento
    @Published var storageTotalGB: Double = 0.0
    @Published var storageUsedGB: Double = 0.0
    @Published var storageFreeGB: Double = 0.0
    @Published var storageUsedPercent: Double = 0.0

    // Formatters / animações compartilhados
    private static let brl: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "pt_BR"); return f
    }()
    nonisolated private static let isoDayParser: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    nonisolated private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "EEE"; return f
    }()
    private static let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.88)
    private static let collapseAnimation = Animation.spring(response: 0.35, dampingFraction: 0.75)
    private static let compactAnimation = Animation.spring(response: 0.4, dampingFraction: 0.7)
    private static let barsAnimation = Animation.easeInOut(duration: 0.12)

    init() {
        Self.cleanupZipLeftovers()
        loadTray()
        loadSettings()

        setupObservers()
        startBatteryMonitoring()
        startVolumeMonitoring()
        startMediaPolling()
        calendar.start()
        privacy.start()
        applyClipboardEnabled()
        applyCapsLockSetting()
        fetchWeather()
        fetchCrypto()
        recomputeLiveActivities()
        updatePollingForVisibility()
    }

    private func applyClipboardEnabled() {
        let enabled = defaults.object(forKey: SettingsKey.clipboardEnabled) as? Bool ?? true
        if enabled && !isSystemAsleep { clipboard.start() } else { clipboard.stop() }
    }

    private var showCapsLockEnabled: Bool {
        defaults.object(forKey: SettingsKey.showCapsLock) as? Bool ?? true
    }

    private func applyCapsLockSetting() {
        if showCapsLockEnabled && !isSystemAsleep {
            capsLockMonitor.start { [weak self] on in self?.capsLockOn = on }
            capsLockOn = capsLockMonitor.isOn
        } else {
            capsLockMonitor.stop()
        }
    }

    // MARK: - Ajustes persistidos

    private var defaults: UserDefaults { .standard }

    private func loadSettings() {
        if defaults.object(forKey: SettingsKey.timerFocusMinutes) != nil {
            timerFocusMinutes = max(1, min(120, defaults.integer(forKey: SettingsKey.timerFocusMinutes)))
        }
        if defaults.object(forKey: SettingsKey.timerBreakMinutes) != nil {
            timerBreakMinutes = max(1, min(120, defaults.integer(forKey: SettingsKey.timerBreakMinutes)))
        }
        if defaults.object(forKey: SettingsKey.timerSoundEnabled) != nil {
            timerSoundEnabled = defaults.bool(forKey: SettingsKey.timerSoundEnabled)
        }
        timerPresetMinutes = timerFocusMinutes
        timerSeconds = timerFocusMinutes * 60
        weatherLocation = defaults.string(forKey: SettingsKey.weatherLocation) ?? ""
        weatherSearchInput = weatherLocation
        hiddenModules = Self.readHiddenModules(defaults)
        readAppearance()
    }

    private func readAppearance() {
        let style = defaults.string(forKey: SettingsKey.surfaceStyle).flatMap(SurfaceStyle.init(rawValue:)) ?? .dynamicGlass
        if style != surfaceStyle { surfaceStyle = style }
        let accent = defaults.string(forKey: SettingsKey.accentChoice).flatMap(AccentChoice.init(rawValue:)) ?? .module
        if accent != accentChoice { accentChoice = accent }
        let solid = defaults.object(forKey: SettingsKey.solidOnLowPower) as? Bool ?? true
        if solid != solidOnLowPower { solidOnLowPower = solid }
    }

    private static func readHiddenModules(_ defaults: UserDefaults) -> Set<NotchModule> {
        let keys = Set(defaults.stringArray(forKey: SettingsKey.hiddenModules) ?? [])
        return Set(NotchModule.userModules.filter { keys.contains($0.storageKey) })
    }

    private func saveHiddenModules() {
        let keys = hiddenModules.map { $0.storageKey }.sorted()
        if (defaults.stringArray(forKey: SettingsKey.hiddenModules) ?? []).sorted() != keys {
            defaults.set(keys, forKey: SettingsKey.hiddenModules)
        }
        recomputeLiveActivities()
        // A aba ativa foi ocultada nos Ajustes: vai para a primeira visível (ou recolhe se não sobrar nenhuma)
        if state == .expanded, !isModuleVisible(activeModule) {
            if let first = visibleModules.first { activeModule = first } else { collapse() }
        }
    }

    /// Chamado quando a tela de Ajustes (ou qualquer um) altera UserDefaults.
    private func reloadExternalSettings() {
        let hidden = Self.readHiddenModules(defaults)
        if hidden != hiddenModules { hiddenModules = hidden }

        if defaults.object(forKey: SettingsKey.timerSoundEnabled) != nil {
            let v = defaults.bool(forKey: SettingsKey.timerSoundEnabled)
            if v != timerSoundEnabled { timerSoundEnabled = v }
        }
        if defaults.object(forKey: SettingsKey.timerFocusMinutes) != nil {
            let v = max(1, min(120, defaults.integer(forKey: SettingsKey.timerFocusMinutes)))
            if v != timerFocusMinutes {
                timerFocusMinutes = v
                if timerIsIdle && timerMode == .focus { setTimerMinutes(v) }
            }
        }
        if defaults.object(forKey: SettingsKey.timerBreakMinutes) != nil {
            let v = max(1, min(120, defaults.integer(forKey: SettingsKey.timerBreakMinutes)))
            if v != timerBreakMinutes {
                timerBreakMinutes = v
                if timerIsIdle && timerMode == .rest { setTimerMinutes(v) }
            }
        }
        let loc = defaults.string(forKey: SettingsKey.weatherLocation) ?? ""
        if loc != weatherLocation {
            weatherSearchInput = loc
            fetchWeather(location: loc)
        }
        readAppearance()
        applyClipboardEnabled()
        if showCapsLockEnabled != (capsLockMonitorRunning) { applyCapsLockSetting() }
        recomputeLiveActivities()
    }

    private var capsLockMonitorRunning: Bool { capsLockMonitor.isRunning }

    private var liveActivitiesEnabled: Bool {
        defaults.object(forKey: SettingsKey.showLiveActivities) as? Bool ?? true
    }

    // MARK: - Observadores

    private func setupObservers() {
        // Ajustes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reloadExternalSettings() }
            .store(in: &cancellables)

        // Live activities dependentes de serviços externos
        calendar.$nextEvent
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeLiveActivities(); self?.updatePollingForVisibility() }
            .store(in: &cancellables)
        Publishers.CombineLatest(privacy.$cameraInUse, privacy.$micInUse)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeLiveActivities() }
            .store(in: &cancellables)

        // Modo de baixa energia
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let low = ProcessInfo.processInfo.isLowPowerModeEnabled
                if low != self.isLowPowerMode { self.isLowPowerMode = low }
                self.fetchBatteryInfo()
            }
            .store(in: &cancellables)

        // Sleep / wake
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.systemWillSleep() }
                .store(in: &cancellables)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.systemDidWake() }
                .store(in: &cancellables)
        }
    }

    private func systemWillSleep() {
        sleepReasons += 1
        guard !isSystemAsleep else { return }
        isSystemAsleep = true
        weatherTimer?.invalidate(); weatherTimer = nil
        calendar.stop()
        privacy.stop()
        github.stop()
        clipboard.stop()
        capsLockMonitor.stop()
        updatePollingForVisibility()
    }

    private func systemDidWake() {
        sleepReasons = max(0, sleepReasons - 1)
        guard isSystemAsleep else { return }
        isSystemAsleep = false
        sleepReasons = 0
        calendar.start()
        privacy.start()
        github.start()
        applyClipboardEnabled()
        applyCapsLockSetting()
        fetchBatteryInfo()
        fetchWeather()
        fetchCrypto()
        updatePollingForVisibility()
    }

    // MARK: - Pollers centralizados

    private func makeTimer(_ interval: TimeInterval, tolerance: Double = 0.15,
                           _ block: @escaping @MainActor () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { block() }
        }
        t.tolerance = interval * tolerance
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    /// Liga/desliga cada poller conforme o que está visível e o estado de sleep.
    func updatePollingForVisibility() {
        let showing = state != .idle
        let current: NotchModule = showing ? activeModule : .none
        let awake = !isSystemAsleep

        // Barras de áudio
        updateAudioBarsForVisibility()

        // Monitor do sistema (CPU/RAM/GPU/armazenamento)
        let needSystem = awake && current == .systemMonitor
        if needSystem, systemTimer == nil {
            fetchSystemStats()
            fetchStorageStats()
            systemTimer = makeTimer(3.0) { [weak self] in self?.fetchSystemStats() }
        } else if !needSystem, systemTimer != nil {
            systemTimer?.invalidate(); systemTimer = nil
        }

        // Crypto: 60s só com o módulo visível
        let needCrypto = awake && current == .crypto
        if needCrypto, cryptoTimer == nil {
            cryptoTimer = makeTimer(60) { [weak self] in self?.fetchCrypto() }
        } else if !needCrypto, cryptoTimer != nil {
            cryptoTimer?.invalidate(); cryptoTimer = nil
        }

        // Clima: a cada 30 min (independe de visibilidade, pausa no sleep)
        if awake, weatherTimer == nil {
            weatherTimer = makeTimer(30 * 60, tolerance: 0.2) { [weak self] in self?.fetchWeather() }
        }

        // Reunião: 30s só se o evento começa em <= 10 min (ou está em andamento);
        // senão, um único disparo quando faltarem 10 min.
        updateMeetingTimer(awake: awake)

        // Ticker da mídia (backend de mídia)
        updateMediaTickerForVisibility()

        // Ao abrir um módulo: atualizar dados velhos
        if current != shownModule {
            shownModule = current
            switch current {
            case .crypto:
                if awake, lastCryptoFetch.map({ Date().timeIntervalSince($0) > 60 }) ?? true { fetchCrypto() }
            case .weather:
                if awake, lastWeatherFetch.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? true { fetchWeather() }
            case .battery:
                refreshBatteryDetails()
            case .github:
                github.refreshIfStale(maxAge: 600)
            default: break
            }
        }
    }

    private func updateMeetingTimer(awake: Bool) {
        meetingTimer?.invalidate(); meetingTimer = nil
        guard awake, let start = calendar.nextEvent?.start else { return }
        let lead = start.timeIntervalSinceNow - 10 * 60
        if lead <= 0 {
            meetingTimer = makeTimer(30, tolerance: 0.2) { [weak self] in
                guard let self else { return }
                self.recomputeLiveActivities()
                if let s = self.calendar.nextEvent?.start, s.timeIntervalSinceNow <= 10 * 60 { return }
                self.updateMeetingTimer(awake: !self.isSystemAsleep)
            }
        } else {
            let t = Timer(timeInterval: lead, repeats: false) { _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.recomputeLiveActivities()
                    self?.updateMeetingTimer(awake: !(self?.isSystemAsleep ?? true))
                }
            }
            t.tolerance = min(30, lead * 0.1)
            RunLoop.main.add(t, forMode: .common)
            meetingTimer = t
        }
    }

    // MARK: - Live Activities

    private func recomputeLiveActivities() {
        var result: [LiveActivity] = []
        if liveActivitiesEnabled {
            if privacy.cameraInUse || privacy.micInUse { result.append(.privacy) }
            if capsLockOn && showCapsLockEnabled { result.append(.capsLock) }
            if stayAwake { result.append(.stayAwake) }
            if timerIsRunning {
                result.append(timerSeconds < 60 ? .timerEnding : .timer)
            }
            if let ev = calendar.nextEvent {
                let now = Date()
                let inProgress = ev.start <= now && ev.end > now
                if inProgress || (ev.start > now && ev.start.timeIntervalSince(now) <= 600) { result.append(.meeting) }
            }
            if mediaIsPlaying { result.append(.media) }
            if batteryIsCharging && batteryLevel < 100 { result.append(.charging) }
        } else if mediaIsPlaying {
            result = [.media]
        }
        result.sort()
        if result != liveActivities { liveActivities = result }
    }

    /// Expande no módulo da atividade primária; senão mídia (se houver player) ou o primeiro módulo visível.
    func openPrimaryActivity() {
        // Atividades sem módulo (ex.: Caps Lock) são ignoradas: usa a próxima com módulo válido.
        if let primary = liveActivities.first(where: { $0.module != .none }) {
            expand(module: primary.module)
        } else if !mediaSource.isEmpty, isModuleVisible(.media) {
            expand(module: .media)
        } else if let first = visibleModules.first {
            expand(module: first)
        }
    }

    // MARK: - Notch State Control

    func expand(module requested: NotchModule) {
        var module = requested
        if !isModuleVisible(module) {
            // Módulo oculto nos Ajustes (ex.: Live Activity de timer com Timer oculto)
            guard let first = visibleModules.first else { return }
            module = first
        }
        compactTask?.cancel()
        withAnimation(Self.expandAnimation) {
            activeModule = module
            state = .expanded
        }
    }

    func collapse() {
        compactTask?.cancel()
        withAnimation(Self.collapseAnimation) {
            state = .idle
            activeModule = .none
        }
    }

    func showCompact(module: NotchModule, duration: Double = 3.0) {
        compactTask?.cancel()
        withAnimation(Self.compactAnimation) {
            activeModule = module
            state = .compact
        }
        compactTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.state == .compact else { return }
            self.collapse()
        }
    }

    // MARK: - Audio Bars Animation

    private func updateAudioBarsForVisibility() {
        let needed = mediaIsPlaying && state != .idle && !isSystemAsleep
        if needed {
            guard audioBarsTimer == nil else { return }
            audioBarsTimer = makeTimer(0.15, tolerance: 0.15) { [weak self] in
                guard let self else { return }
                withAnimation(Self.barsAnimation) {
                    self.audioBars = self.audioBars.map { _ in CGFloat.random(in: 0.15...1.0) }
                }
            }
        } else {
            audioBarsTimer?.invalidate(); audioBarsTimer = nil
            let rest = audioBars.map { _ in CGFloat(0.15) }
            if audioBars != rest { audioBars = rest }
        }
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        fetchBatteryInfo()
        powerMonitor.start { [weak self] in
            MainActor.assumeIsolated { self?.fetchBatteryInfo() }
        }
    }

    private func refreshBatteryDetails() {
        let details = BatteryDetails.read()
        if details != batteryDetails { batteryDetails = details }
    }

    func fetchBatteryInfo() {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]

        guard let source = sources?.first else { return }
        let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]

        let level = info?[kIOPSCurrentCapacityKey as String] as? Int ?? batteryLevel
        let charging = (info?[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue

        refreshBatteryDetails()
        let wasCharging = batteryIsCharging
        let oldLevel = batteryLevel

        batteryLevel = level
        batteryIsCharging = charging

        // Alerta de bateria baixa
        if !charging && (level == 20 || level == 10) && oldLevel > level {
            showCompact(module: .battery, duration: 5.0)
        }

        // Alerta ao conectar/desconectar carregador
        if charging != wasCharging {
            showCompact(module: .battery, duration: 3.0)
        }
    }

    // MARK: - Timer Module

    func startTimer() {
        if timerSeconds == 0 { timerSeconds = timerPresetMinutes * 60 }
        timerIsRunning = true
        timerEndDate = Date().addingTimeInterval(TimeInterval(timerSeconds))

        timerCancellable?.cancel()
        // Baseado em data final: continua correto após sleep.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerTick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        timerCancellable = AnyCancellable { timer.invalidate() }
    }

    private func timerTick() {
        guard timerIsRunning, let end = timerEndDate else { return }
        let remaining = Int(end.timeIntervalSinceNow.rounded(.up))
        if remaining > 0 {
            if remaining != timerSeconds { timerSeconds = remaining }
        } else {
            timerSeconds = 0
            timerIsRunning = false
            timerEndDate = nil
            timerCancellable?.cancel()
            timerFinished()
        }
    }

    func pauseTimer() {
        timerIsRunning = false
        timerEndDate = nil
        timerCancellable?.cancel()
    }

    func resetTimer() {
        timerIsRunning = false
        timerEndDate = nil
        timerCancellable?.cancel()
        timerSeconds = timerPresetMinutes * 60
    }

    /// Escolhe a duração (régua). Só vale com o timer parado.
    func setTimerMinutes(_ minutes: Int) {
        guard !timerIsRunning else { return }
        let m = max(1, min(120, minutes))
        timerPresetMinutes = m
        timerSeconds = m * 60
        if timerMode == .focus { timerFocusMinutes = m } else { timerBreakMinutes = m }
    }

    func setTimerMode(_ mode: TimerMode) {
        guard !timerIsRunning, mode != timerMode else { return }
        timerMode = mode
        setTimerMinutes(mode == .focus ? timerFocusMinutes : timerBreakMinutes)
    }

    var timerDisplay: String {
        let mins = timerSeconds / 60
        let secs = timerSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func timerFinished() {
        let finishedMode = timerMode
        let minutes = timerPresetMinutes
        if timerSoundEnabled { NSSound(named: "Glass")?.play() }

        let content = UNMutableNotificationContent()
        content.title = finishedMode == .focus ? "Focus concluído" : "Pausa concluída"
        content.body = finishedMode == .focus ? "Você focou por \(minutes) min. Hora de uma pausa!" : "Pausa de \(minutes) min acabou. Bora voltar ao foco!"
        content.sound = timerSoundEnabled ? nil : .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil), withCompletionHandler: nil)

        // Sugere o próximo modo (sem iniciar sozinho)
        timerMode = finishedMode == .focus ? .rest : .focus
        setTimerMinutes(timerMode == .focus ? timerFocusMinutes : timerBreakMinutes)
        showCompact(module: .timer, duration: 4.0)
    }

    // MARK: - Volume do sistema (CoreAudio)

    private func startVolumeMonitoring() {
        if let r = audioVolume.read() {
            systemVolume = r.volume
            systemMuted = r.muted
        }
        audioVolume.onChange = { [weak self] reading in
            MainActor.assumeIsolated { self?.systemVolumeChanged(reading) }
        }
        audioVolume.start()
    }

    private func systemVolumeChanged(_ r: SystemAudioVolume.Reading) {
        let changed = abs(r.volume - systemVolume) > 0.0001 || r.muted != systemMuted
        guard changed else { return }
        systemVolume = r.volume
        systemMuted = r.muted
        let hud = defaults.object(forKey: SettingsKey.showVolumeHUD) as? Bool ?? true
        if hud && state != .expanded {
            showCompact(module: .volume, duration: 1.5)
        }
    }

    // MARK: - Estatísticas do sistema

    private func fetchSystemStats() {
        guard !isFetchingSystemStats else { return }
        isFetchingSystemStats = true
        // Ponteiros Mach viajam como endereços (Sendable) entre threads
        let prevAddr = previousCpuInfo.map { UInt(bitPattern: $0) }
        let prevCount = previousCpuInfoCount

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // --- 1. RAM VIA MACH HOST STATISTICS ---
            let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            var vmStats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

            let hostPort = mach_host_self()
            let ramResult = withUnsafeMutablePointer(to: &vmStats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
                }
            }

            var calculatedRamPercent: Double?
            if ramResult == KERN_SUCCESS {
                let pageSize = Double(vm_kernel_page_size)

                let activeBytes = Double(vmStats.active_count) * pageSize
                let wiredBytes = Double(vmStats.wire_count) * pageSize
                let compressedBytes = Double(vmStats.compressor_page_count) * pageSize

                let usedBytes = activeBytes + wiredBytes + compressedBytes
                calculatedRamPercent = min(100.0, max(0.0, (usedBytes / totalBytes) * 100.0))
            }

            // --- 2. CPU VIA MACH PROCESSOR INFO ---
            var numCPUs: natural_t = 0
            var cpuInfo: processor_info_array_t?
            var numCpuInfo: mach_msg_type_number_t = 0

            let cpuResult = host_processor_info(
                hostPort,
                PROCESSOR_CPU_LOAD_INFO,
                &numCPUs,
                &cpuInfo,
                &numCpuInfo
            )

            var calculatedCpuPercent: Double?
            var newAddr: UInt?
            if cpuResult == KERN_SUCCESS, let currentCpuInfo = cpuInfo {
                newAddr = UInt(bitPattern: currentCpuInfo)
                if let prevAddr, let prevInfo = UnsafeMutablePointer<integer_t>(bitPattern: prevAddr) {
                    var totalInUse: Int64 = 0
                    var totalTotal: Int64 = 0

                    for i in 0..<Int(numCPUs) {
                        let base = i * Int(CPU_STATE_MAX)

                        let user = Int64(currentCpuInfo[base + Int(CPU_STATE_USER)] - prevInfo[base + Int(CPU_STATE_USER)])
                        let system = Int64(currentCpuInfo[base + Int(CPU_STATE_SYSTEM)] - prevInfo[base + Int(CPU_STATE_SYSTEM)])
                        let nice = Int64(currentCpuInfo[base + Int(CPU_STATE_NICE)] - prevInfo[base + Int(CPU_STATE_NICE)])
                        let idle = Int64(currentCpuInfo[base + Int(CPU_STATE_IDLE)] - prevInfo[base + Int(CPU_STATE_IDLE)])

                        let inUse = user + system + nice
                        let total = inUse + idle

                        totalInUse += inUse
                        totalTotal += total
                    }

                    if totalTotal > 0 {
                        let percent = (Double(totalInUse) / Double(totalTotal)) * 100.0
                        calculatedCpuPercent = min(100.0, max(0.0, percent))
                    }

                    // Desaloca a memória anterior do buffer Mach
                    let prevSize = vm_size_t(prevCount) * vm_size_t(MemoryLayout<integer_t>.size)
                    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), prevSize)
                }
            }

            let gpu = NotchViewModel.readGPUUsage()
            let ram = calculatedRamPercent
            let cpu = calculatedCpuPercent
            let savedAddr = newAddr
            let savedCount = numCpuInfo

            // --- 3. ATUALIZAÇÃO DA UI E DO ESTADO NO MAINACTOR ---
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isFetchingSystemStats = false

                if let ram { self.ramUsage = ram }
                if let cpu { self.cpuUsage = cpu }
                if let gpu { self.gpuUsage = gpu }
                self.cpuHistory = Array((self.cpuHistory + [self.cpuUsage]).suffix(24))
                self.gpuHistory = Array((self.gpuHistory + [self.gpuUsage]).suffix(24))
                self.ramHistory = Array((self.ramHistory + [self.ramUsage]).suffix(24))

                // Guarda o buffer atual (na main) para o próximo cálculo
                if let savedAddr {
                    self.previousCpuInfo = UnsafeMutablePointer<integer_t>(bitPattern: savedAddr)
                    self.previousCpuInfoCount = savedCount
                }
            }
        }
    }

    /// Utilização da GPU (%) via IOAccelerator → PerformanceStatistics.
    nonisolated private static func readGPUUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let util = (props["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, util)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best.map { min(100, max(0, $0)) }
    }

    // MARK: - Rede (helper com retry/backoff)

    private enum FetchOutcome: Sendable {
        case success(Data)
        case httpError(Int)
        case offline
        case cancelled
        case failed(String)
    }

    nonisolated private static func isOfflineError(_ e: URLError) -> Bool {
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed:
            return true
        default: return false
        }
    }

    /// GET com timeout, até `attempts` tentativas com backoff exponencial (1s, 2s...).
    nonisolated private static func fetch(_ url: URL, attempts: Int = 3) async -> FetchOutcome {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MyOwnNotch", forHTTPHeaderField: "User-Agent")
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    if http.statusCode >= 500, attempt < attempts {
                        try await Task.sleep(for: .seconds(pow(2, Double(attempt - 1))))
                        continue
                    }
                    return .httpError(http.statusCode)
                }
                return .success(data)
            } catch is CancellationError {
                return .cancelled
            } catch let e as URLError {
                if e.code == .cancelled { return .cancelled }
                if isOfflineError(e) { return .offline }
                if attempt < attempts {
                    do { try await Task.sleep(for: .seconds(pow(2, Double(attempt - 1)))) } catch { return .cancelled }
                    continue
                }
                return .failed(e.code == .timedOut ? "Tempo esgotado" : e.localizedDescription)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Clima

    /// `location == nil` usa o local salvo; string (inclusive vazia = automático) é salva e usada.
    func fetchWeather(location: String? = nil) {
        if let location {
            let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
            weatherLocation = trimmed
            if defaults.string(forKey: SettingsKey.weatherLocation) != trimmed {
                defaults.set(trimmed, forKey: SettingsKey.weatherLocation)
            }
        }
        let loc = weatherLocation
        guard let url = Self.weatherURL(location: loc) else {
            weatherStatus = .failed("Local não encontrado")
            return
        }
        weatherTask?.cancel()
        weatherStatus = .loading
        weatherTask = Task { [weak self] in
            let outcome = await Self.fetch(url)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .cancelled:
                return
            case .offline:
                self.weatherStatus = .offline
            case .httpError(let code):
                self.weatherStatus = .failed(code == 404 ? "Local não encontrado" : "Erro do servidor (\(code))")
            case .failed(let message):
                self.weatherStatus = .failed(message)
            case .success(let data):
                guard let parsed = Self.parseWeather(data) else {
                    self.weatherStatus = .failed("Local não encontrado")
                    return
                }
                self.applyWeather(parsed)
            }
        }
    }

    private func applyWeather(_ w: ParsedWeather) {
        weatherTemp = w.temp
        weatherDesc = w.desc
        weatherLocationDisplay = w.locationName
        weatherFeelsLike = w.feelsLike
        weatherHumidity = w.humidity
        weatherWind = w.wind
        weatherHigh = w.high
        weatherLow = w.low
        weatherIsDay = w.isDay
        weatherIcon = w.icon
        weatherForecast = w.forecast
        lastWeatherFetch = Date()
        weatherStatus = .loaded
    }

    /// Monta a URL com o local codificado (sem permitir "/", "?", "&" que alterariam o path/query).
    nonisolated static func weatherURL(location: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wttr.in"
        if !location.isEmpty {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "/?&#+%")
            guard let encoded = location.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            components.percentEncodedPath = "/" + encoded
        }
        components.queryItems = [URLQueryItem(name: "format", value: "j1")]
        return components.url
    }

    /// Parse puro do JSON do wttr.in (testável). Retorna nil se a resposta não for um JSON válido.
    nonisolated static func parseWeather(_ data: Data) -> ParsedWeather? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let current = (json["current_condition"] as? [[String: Any]])?.first else { return nil }

        func value(_ dict: [String: Any]?, _ key: String) -> String? {
            if let s = dict?[key] as? String { return s }
            if let n = dict?[key] as? NSNumber { return n.stringValue }
            return nil
        }

        let temp = value(current, "temp_C") ?? "--"
        let desc = ((current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String) ?? "Desconhecido"
        let isDay = (current["isdaytime"] as? String ?? "yes") == "yes"
        let days = (json["weather"] as? [[String: Any]]) ?? []
        let today = days.first

        let forecast: [WeatherDay] = days.prefix(3).enumerated().map { i, day in
            let hourly = day["hourly"] as? [[String: Any]]
            let noon = (hourly?.count ?? 0) > 4 ? hourly?[4] : hourly?.first   // ~12h
            let d = ((noon?["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String) ?? ""
            let dateString = day["date"] as? String
            let date = dateString.flatMap { isoDayParser.date(from: $0) }
            let label = i == 0 ? "Hoje"
                : (date.map { weekdayFormatter.string(from: $0).capitalized.replacingOccurrences(of: ".", with: "") } ?? "--")
            return WeatherDay(
                id: dateString ?? "day-\(i)",
                label: label,
                icon: weatherSymbol(d, isDay: true),
                high: "\(value(day, "maxtempC") ?? "--")°",
                low: "\(value(day, "mintempC") ?? "--")°")
        }

        let area = (json["nearest_area"] as? [[String: Any]])?.first
        let areaName = (area?["areaName"] as? [[String: Any]])?.first?["value"] as? String ?? "Localização"

        return ParsedWeather(
            temp: "\(temp)°C",
            desc: desc,
            icon: weatherSymbol(desc, isDay: isDay),
            feelsLike: "\(value(current, "FeelsLikeC") ?? "--")°",
            humidity: "\(value(current, "humidity") ?? "--")%",
            wind: "\(value(current, "windspeedKmph") ?? "--") km/h",
            high: "\(value(today, "maxtempC") ?? "--")°",
            low: "\(value(today, "mintempC") ?? "--")°",
            isDay: isDay,
            locationName: areaName,
            forecast: forecast)
    }

    /// SF Symbol para a descrição do wttr.in
    nonisolated static func weatherSymbol(_ desc: String, isDay: Bool) -> String {
        let d = desc.lowercased()
        if d.contains("thunder") { return "cloud.bolt.rain.fill" }
        if d.contains("sun") || d.contains("clear") { return isDay ? "sun.max.fill" : "moon.stars.fill" }
        if d.contains("rain") || d.contains("shower") || d.contains("drizzle") { return "cloud.rain.fill" }
        if d.contains("snow") || d.contains("sleet") { return "snowflake" }
        if d.contains("fog") || d.contains("mist") { return "cloud.fog.fill" }
        if d.contains("overcast") || d.contains("cloudy") { return "cloud.fill" }
        return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
    }

    // MARK: - Crypto

    func fetchCrypto() {
        let coinsToFetch = [("BTC", "Bitcoin", "BTC-BRL"), ("USD", "Dólar", "USD-BRL"), ("EUR", "Euro", "EUR-BRL")]
        cryptoTask?.cancel()
        cryptoStatus = .loading
        cryptoTask = Task { [weak self] in
            let results: [(String, String, FetchOutcome)] = await withTaskGroup(of: (String, String, FetchOutcome).self) { group in
                for coin in coinsToFetch {
                    group.addTask {
                        guard let url = URL(string: "https://economia.awesomeapi.com.br/json/daily/\(coin.2)/30") else {
                            return (coin.0, coin.1, .failed("URL inválida"))
                        }
                        return (coin.0, coin.1, await Self.fetch(url))
                    }
                }
                var all: [(String, String, FetchOutcome)] = []
                for await r in group { all.append(r) }
                return all
            }
            guard !Task.isCancelled, let self else { return }

            var succeeded = 0, offline = 0, cancelled = 0
            var lastError = "Falha ao atualizar"
            for (symbol, name, outcome) in results {
                switch outcome {
                case .success(let data):
                    if let coin = Self.parseCoin(data, symbol: symbol, name: name),
                       let idx = self.cryptoCoins.firstIndex(where: { $0.symbol == symbol }) {
                        self.cryptoCoins[idx] = coin
                        succeeded += 1
                    } else { lastError = "Resposta inválida" }
                case .offline: offline += 1
                case .cancelled: cancelled += 1
                case .httpError(let code): lastError = "Erro do servidor (\(code))"
                case .failed(let message): lastError = message
                }
            }
            if cancelled == results.count { return }
            if succeeded > 0 {
                self.lastCryptoFetch = Date()
                self.cryptoStatus = .loaded
            } else if offline > 0 {
                self.cryptoStatus = .offline
            } else {
                self.cryptoStatus = .failed(lastError)
            }
        }
    }

    private static func parseCoin(_ data: Data, symbol: String, name: String) -> CryptoCoin? {
        guard let jsonArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let today = jsonArray.first,
              let bid = today["bid"] as? String, let pct = today["pctChange"] as? String,
              let d = Double(bid) else { return nil }
        let isPos = !pct.hasPrefix("-")
        let fmt = d >= 1000 ? "R$ " + (brl.string(from: NSNumber(value: d)) ?? String(format: "%.0f", d)) : String(format: "R$ %.2f", d)
        let history: [CGFloat] = jsonArray.compactMap { item in
            (item["bid"] as? String).flatMap(Double.init).map { CGFloat($0) }
        }.reversed()
        return CryptoCoin(
            symbol: symbol, name: name, price: fmt, change: "\(pct)%", isPositive: isPos,
            points: history.isEmpty ? (isPos ? [2,3,2,5,4,7,6,8,7,9] : [9,8,9,6,7,4,5,3,4,2]) : history)
    }

    // MARK: - Armazenamento

    func fetchStorageStats() {
        Task { [weak self] in
            guard let (totalGB, freeGB) = await Self.readStorage(), let self else { return }
            let usedGB = max(0, totalGB - freeGB)
            self.storageTotalGB = totalGB
            self.storageUsedGB = usedGB
            self.storageFreeGB = freeGB
            self.storageUsedPercent = totalGB > 0 ? min(100.0, max(0.0, usedGB / totalGB * 100.0)) : 0
        }
    }

    nonisolated private static func readStorage() async -> (Double, Double)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let homeURL = URL(fileURLWithPath: NSHomeDirectory())
                guard let values = try? homeURL.resourceValues(forKeys: [
                        .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
                      let total = values.volumeTotalCapacity,
                      let free = values.volumeAvailableCapacityForImportantUsage else {
                    continuation.resume(returning: nil); return
                }
                let gb = 1_073_741_824.0
                continuation.resume(returning: (Double(total) / gb, Double(free) / gb))
            }
        }
    }

    // MARK: - Quick Actions

    /// Executa AppleScript fora da main; em -1743 (automação negada) sinaliza `automationDenied`.
    private static let log = Logger(subsystem: "MyOwnNotch", category: "AppleScript")

    private func runAppleScript(_ source: String) {
        Task { [weak self] in
            let (code, message) = await Self.executeAppleScript(source)
            if code == -1743 { self?.automationDenied = true }
            else if let message { Self.log.error("AppleScript falhou (\(code ?? 0)): \(message, privacy: .private)") }
        }
    }

    nonisolated private static func executeAppleScript(_ source: String) async -> (Int?, String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                let code = (errorInfo?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                let message = errorInfo?[NSAppleScript.errorMessage] as? String
                continuation.resume(returning: (code, message))
            }
        }
    }

    func lockScreen() {
        runAppleScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
    }

    func emptyTrash() {
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    func sleepMac() {
        runAppleScript("tell application \"Finder\" to sleep")
    }

    // MARK: - Tray (bandeja de arquivos)

    private func loadTray() {
        let paths = UserDefaults.standard.stringArray(forKey: trayDefaultsKey) ?? []
        trayItems = paths.map { TrayItem(url: URL(fileURLWithPath: $0)) }.filter { $0.exists }
    }

    private func saveTray() {
        UserDefaults.standard.set(trayItems.map { $0.url.path }, forKey: trayDefaultsKey)
    }

    func addToTray(_ urls: [URL]) {
        var added = false
        for url in urls where !trayItems.contains(where: { $0.url == url }) {
            trayItems.append(TrayItem(url: url))
            added = true
        }
        if added { saveTray() }
        // Mostra a bandeja assim que algo é solto
        if state != .expanded || activeModule != .tray { expand(module: .tray) }
    }

    func removeFromTray(_ item: TrayItem) {
        trayItems.removeAll { $0.id == item.id }
        saveTray()
        Self.deleteIfInTrayZips(item.url)
    }

    func clearTray() {
        let old = trayItems
        trayItems.removeAll()
        saveTray()
        old.forEach { Self.deleteIfInTrayZips($0.url) }
    }

    nonisolated private static func trayZipsDir() -> URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        return support.appendingPathComponent("MyOwnNotch/TrayZips", isDirectory: true)
    }

    /// Apaga do disco apenas arquivos que estejam dentro de TrayZips (nunca originais do usuário).
    nonisolated private static func deleteIfInTrayZips(_ url: URL) {
        guard let dir = trayZipsDir() else { return }
        let base = dir.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        if file.path.hasPrefix(base) { try? FileManager.default.removeItem(at: file) }
    }

    /// Remove diretórios temporários órfãos "MyOwnNotchZip-*" e zips com mais de 7 dias.
    nonisolated private static func cleanupZipLeftovers() {
        let fm = FileManager.default
        DispatchQueue.global(qos: .utility).async {
            let tmp = fm.temporaryDirectory
            for u in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            where u.lastPathComponent.hasPrefix("MyOwnNotchZip-") {
                try? fm.removeItem(at: u)
            }
            guard let dir = trayZipsDir() else { return }
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension.lowercased() == "zip" {
                let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let d, d < cutoff { try? fm.removeItem(at: f) }
            }
        }
    }

    /// Nome seguro para o zip: sem separadores, sem '.' inicial.
    nonisolated static func sanitizedZipBaseName(_ raw: String) -> String {
        var n = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Arquivo" : n
    }

    /// Compacta os itens (ou a bandeja inteira) com /usr/bin/ditto e adiciona o .zip à bandeja.
    /// Destino: ~/Library/Application Support/MyOwnNotch/TrayZips (nunca sobrescreve: "nome 2.zip"...).
    /// Um item -> "<nome>.zip"; vários -> "Arquivo.zip" (copiados para dir temporário, que é zipado).
    func zipTrayItems(_ items: [TrayItem]? = nil) {
        guard !trayIsZipping else { return }
        let urls = (items ?? trayItems).map { $0.url.resolvingSymlinksInPath() }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        trayIsZipping = true
        trayZipError = nil
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Self.createZip(of: urls) }.value
            guard let self else { return }
            self.trayIsZipping = false
            switch result {
            case .success(let zip):
                self.addToTray([zip])
            case .failure(let error):
                self.trayZipError = error.message
            }
        }
    }

    private struct ZipError: Error { let message: String }

    nonisolated private static func createZip(of urls: [URL]) -> Result<URL, ZipError> {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let outDir = support.appendingPathComponent("MyOwnNotch/TrayZips", isDirectory: true)
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

            let baseName = sanitizedZipBaseName(urls.count == 1 ? urls[0].lastPathComponent : "Arquivo")
            let outPrefix = outDir.standardizedFileURL.path + "/"
            var dest = outDir.appendingPathComponent(baseName + ".zip")
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = outDir.appendingPathComponent("\(baseName) \(n).zip"); n += 1
            }
            guard dest.standardizedFileURL.path.hasPrefix(outPrefix) else {
                return .failure(ZipError(message: "Nome de arquivo inválido"))
            }

            var source = urls[0]
            var tempRoot: URL?
            defer { if let tempRoot { try? fm.removeItem(at: tempRoot) } }
            if urls.count > 1 {
                let root = fm.temporaryDirectory.appendingPathComponent("MyOwnNotchZip-\(UUID().uuidString)", isDirectory: true)
                let folder = root.appendingPathComponent(baseName, isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                tempRoot = root
                for u in urls {
                    let resolved = u.resolvingSymlinksInPath()
                    guard fm.fileExists(atPath: resolved.path) else { continue }
                    var target = folder.appendingPathComponent(sanitizedZipBaseName(u.lastPathComponent))
                    var k = 2
                    while fm.fileExists(atPath: target.path) {
                        target = folder.appendingPathComponent("\(k)-" + u.lastPathComponent); k += 1
                    }
                    try fm.copyItem(at: resolved, to: target)
                }
                source = folder
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, dest.path]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = FileHandle.nullDevice
            try p.run()
            var timedOut = false
            let lock = NSLock()
            let killer = DispatchWorkItem {
                lock.lock(); timedOut = true; lock.unlock()
                if p.isRunning { p.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: killer)
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            lock.lock(); let didTimeOut = timedOut; lock.unlock()
            if didTimeOut {
                try? fm.removeItem(at: dest)
                return .failure(ZipError(message: "Tempo esgotado ao comprimir"))
            }
            guard p.terminationStatus == 0 else {
                try? fm.removeItem(at: dest)
                let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .failure(ZipError(message: msg.isEmpty ? "Falha ao compactar" : msg))
            }
            return .success(dest)
        } catch {
            return .failure(ZipError(message: error.localizedDescription))
        }
    }

    /// Lê as URLs de arquivo dos providers de um drop.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }
        Task { [weak self] in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await Self.loadURL(from: provider), url.isFileURL { urls.append(url) }
            }
            guard !urls.isEmpty else { return }
            self?.addToTray(urls)
        }
        return true
    }

    nonisolated private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
