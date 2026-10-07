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

enum NotchModule: Equatable {
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

// MARK: - ViewModel


@MainActor
class NotchViewModel: ObservableObject {

    // Estado visual
    @Published var state: NotchState = .idle
    @Published var activeModule: NotchModule = .none
    @Published var isVisible: Bool = true
    @Published var isHovered: Bool = false
    @Published var metrics: NotchMetrics = NotchMetrics.measure(NotchMetrics.preferredScreen())

    var islandSize: CGSize {
        metrics.islandSize(for: state, mediaPlaying: mediaIsPlaying, module: activeModule)
    }

    // Módulo de Mídia
    @Published var mediaTitle: String = "Nenhuma mídia"
    @Published var mediaArtist: String = ""
    @Published var mediaIsPlaying: Bool = false
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
    @Published var batteryLevel: Int = 100
    @Published var batteryIsCharging: Bool = false
    @Published var batteryDetails = BatteryDetails.read()

    // Módulo de Timer
    @Published var timerSeconds: Int = 25 * 60
    @Published var timerIsRunning: Bool = false
    @Published var timerPresetMinutes: Int = 25
    @Published var timerMode: TimerMode = .focus
    @Published var timerSoundEnabled: Bool = true
    var timerFocusMinutes = 25
    var timerBreakMinutes = 5
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
    
    @Published var cryptoCoins: [CryptoCoin] = [
        CryptoCoin(symbol: "BTC", name: "Bitcoin", price: "...", change: "0", isPositive: true, points: [1,1,1]),
        CryptoCoin(symbol: "USD", name: "Dólar", price: "...", change: "0", isPositive: true, points: [1,1,1]),
        CryptoCoin(symbol: "EUR", name: "Euro", price: "...", change: "0", isPositive: true, points: [1,1,1])
    ]
    
    @Published var currentVolume: Int = 50
    private var lastVolume: Int = -1
    
    // Terminal
    let terminal = TerminalSession()
    let agent = AgentSession()
    let spotify = SpotifyService()
    var mediaTrackURI = ""

    // Bandeja de arquivos
    @Published var trayItems: [TrayItem] = []
    @Published var isDropTargeted: Bool = false
    private let trayDefaultsKey = "trayPaths"

    private var timerCancellable: AnyCancellable?
    private var audioBarsTimer: AnyCancellable?
    var mediaPoller: AnyCancellable?
    var mediaTicker: AnyCancellable?
    private var batteryPoller: AnyCancellable?
    private var systemPoller: AnyCancellable?
    private var volumePoller: AnyCancellable?

    // Módulo de Armazenamento
    @Published var storageTotalGB: Double = 0.0
    @Published var storageUsedGB: Double = 0.0
    @Published var storageFreeGB: Double = 0.0
    @Published var storageUsedPercent: Double = 0.0

    private static let brl: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "pt_BR"); return f
    }()

    private var cryptoPoller: AnyCancellable?

    init() {
        loadTray()
        cryptoPoller = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.fetchCrypto() }
        startAudioBarsAnimation()
        startMediaPolling()
        startBatteryMonitoring()
        startSystemAndVolumePolling()
        fetchWeather()
        fetchCrypto()
    }

    // MARK: - Notch State Control

    func expand(module: NotchModule) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            activeModule = module
            state = .expanded
        }
    }

    func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            state = .idle
            activeModule = .none
        }
    }

    func showCompact(module: NotchModule, duration: Double = 3.0) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            activeModule = module
            state = .compact
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            if self.state == .compact {
                self.collapse()
            }
        }
    }

    // MARK: - Audio Bars Animation

    private func startAudioBarsAnimation() {
        audioBarsTimer = Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.mediaIsPlaying {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        self.audioBars = self.audioBars.map { _ in
                            CGFloat.random(in: 0.15...1.0)
                        }
                    }
                } else {
                    self.audioBars = self.audioBars.map { _ in 0.15 }
                }
            }
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        fetchBatteryInfo()
        batteryPoller = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchBatteryInfo()
            }
    }

    func fetchBatteryInfo() {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]

        guard let source = sources?.first else { return }
        let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]

        let level = info?[kIOPSCurrentCapacityKey as String] as? Int ?? batteryLevel
        let charging = (info?[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue

        batteryDetails = BatteryDetails.read()
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

        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timerSeconds > 1 {
                    self.timerSeconds -= 1
                } else {
                    self.timerSeconds = 0
                    self.timerIsRunning = false
                    self.timerCancellable?.cancel()
                    self.timerFinished()
                }
            }
    }

    func pauseTimer() {
        timerIsRunning = false
        timerCancellable?.cancel()
    }

    func resetTimer() {
        timerIsRunning = false
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

    // MARK: - Novos Módulos (System, Weather, Volume, Actions)
    
    private func startSystemAndVolumePolling() {
        // CPU e RAM a cada 3 segundos
        systemPoller = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchSystemStats()
            }
            
        // Volume a cada 0.5s para resposta rápida
        volumePoller = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchVolume()
            }
            
        fetchSystemStats()
        fetchStorageStats()
        fetchVolume()
    }
    
private func fetchSystemStats() {
        // Captura os dados anteriores no MainActor antes de ir para background
        let prevInfo = self.previousCpuInfo
        let prevCount = self.previousCpuInfoCount
        
        DispatchQueue.global(qos: .utility).async {
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
            if cpuResult == KERN_SUCCESS, let currentCpuInfo = cpuInfo {
                if let prevInfo = prevInfo {
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
            
            // --- 3. ATUALIZAÇÃO DA UI E DO ESTADO NO MAINACTOR ---
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if let ram = calculatedRamPercent {
                    self.ramUsage = ram
                }
                if let cpu = calculatedCpuPercent {
                    self.cpuUsage = cpu
                }
                if let gpu = Self.readGPUUsage() {
                    self.gpuUsage = gpu
                }
                self.cpuHistory = Array((self.cpuHistory + [self.cpuUsage]).suffix(24))
                self.gpuHistory = Array((self.gpuHistory + [self.gpuUsage]).suffix(24))
                self.ramHistory = Array((self.ramHistory + [self.ramUsage]).suffix(24))
                
                // Salva o buffer atualizado com segurança na Main Thread
                if cpuResult == KERN_SUCCESS, let currentCpuInfo = cpuInfo {
                    self.previousCpuInfo = currentCpuInfo
                    self.previousCpuInfoCount = numCpuInfo
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

    private func fetchVolume() {
        let script = "output volume of (get volume settings)"
        DispatchQueue.global(qos: .background).async {
            if let scriptObj = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                let result = scriptObj.executeAndReturnError(&errorInfo)
                if let volStr = result.stringValue, let vol = Int(volStr) {
                    DispatchQueue.main.async {
                        if self.lastVolume != -1 && self.lastVolume != vol {
                            // Volume mudou! Mostra no notch
                            self.currentVolume = vol
                            if self.state == .idle || self.activeModule == .volume {
                                self.showCompact(module: .volume, duration: 2.0)
                            }
                        }
                        if self.lastVolume == -1 { self.currentVolume = vol }
                        self.lastVolume = vol
                    }
                }
            }
        }
    }
    
    func fetchWeather(location: String = "") {
        let locQuery = location.isEmpty ? "" : "/\(location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        guard let url = URL(string: "https://wttr.in\(locQuery)?format=j1") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = (json["current_condition"] as? [[String: Any]])?.first {
                
                let temp = current["temp_C"] as? String ?? "--"
                let descArray = current["weatherDesc"] as? [[String: Any]]
                let desc = descArray?.first?["value"] as? String ?? "Desconhecido"
                
                let feels = current["FeelsLikeC"] as? String ?? "--"
                let humidity = current["humidity"] as? String ?? "--"
                let wind = current["windspeedKmph"] as? String ?? "--"
                let today = (json["weather"] as? [[String: Any]])?.first
                let hi = today?["maxtempC"] as? String ?? "--"
                let lo = today?["mintempC"] as? String ?? "--"
                let isDay = (current["isdaytime"] as? String ?? "yes") == "yes"

                let area = (json["nearest_area"] as? [[String: Any]])?.first
                let areaName = (area?["areaName"] as? [[String: Any]])?.first?["value"] as? String ?? "Localização"
                
                DispatchQueue.main.async {
                    self.weatherTemp = "\(temp)°C"
                    self.weatherDesc = desc
                    self.weatherLocationDisplay = areaName
                    self.weatherFeelsLike = "\(feels)°"
                    self.weatherHumidity = "\(humidity)%"
                    self.weatherWind = "\(wind) km/h"
                    self.weatherHigh = "\(hi)°"
                    self.weatherLow = "\(lo)°"
                    self.weatherIsDay = isDay
                    
                    let lowerDesc = desc.lowercased()
                    if lowerDesc.contains("sun") || lowerDesc.contains("clear") { self.weatherIcon = isDay ? "sun.max.fill" : "moon.stars.fill" }
                    else if lowerDesc.contains("rain") || lowerDesc.contains("shower") { self.weatherIcon = "cloud.rain.fill" }
                    else if lowerDesc.contains("cloud") || lowerDesc.contains("overcast") { self.weatherIcon = "cloud.fill" }
                    else if lowerDesc.contains("snow") { self.weatherIcon = "snowflake" }
                    else { self.weatherIcon = "cloud.sun.fill" }
                }
            }
        }.resume()
    }
    
    func fetchCrypto() {
        let coinsToFetch = [("BTC", "Bitcoin", "BTC-BRL"), ("USD", "Dólar", "USD-BRL"), ("EUR", "Euro", "EUR-BRL")]
        
        for coinInfo in coinsToFetch {
            guard let url = URL(string: "https://economia.awesomeapi.com.br/json/daily/\(coinInfo.2)/30") else { continue }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      let today = jsonArray.first else { return }
                
                DispatchQueue.main.async {
                    if let bid = today["bid"] as? String, let pct = today["pctChange"] as? String, let d = Double(bid) {
                        let isPos = !(pct.hasPrefix("-"))
                        let fmt = d >= 1000 ? "R$ " + (Self.brl.string(from: NSNumber(value: d)) ?? String(format: "%.0f", d)) : String(format: "R$ %.2f", d)
                        
                        let historyPoints: [CGFloat] = jsonArray.compactMap { item in
                            if let b = item["bid"] as? String, let val = Double(b) {
                                return CGFloat(val)
                            }
                            return nil
                        }.reversed()
                        
                        let newCoin = CryptoCoin(
                            symbol: coinInfo.0,
                            name: coinInfo.1,
                            price: fmt,
                            change: "\(pct)%",
                            isPositive: isPos,
                            points: historyPoints.isEmpty ? (isPos ? [2,3,2,5,4,7,6,8,7,9] : [9,8,9,6,7,4,5,3,4,2]) : historyPoints
                        )
                        
                        if let idx = self.cryptoCoins.firstIndex(where: { $0.symbol == coinInfo.0 }) {
                            self.cryptoCoins[idx] = newCoin
                        }
                    }
                }
            }.resume()
        }
    }

    func fetchStorageStats() {
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            
            do {
                let values = try homeURL.resourceValues(forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityForImportantUsageKey
                ])
                
                if let totalBytes = values.volumeTotalCapacity,
                   let freeBytes = values.volumeAvailableCapacityForImportantUsage {
                    
                    let bytesInGB = 1_073_741_824.0
                    let totalGB = Double(totalBytes) / bytesInGB
                    let freeGB = Double(freeBytes) / bytesInGB
                    let usedGB = max(0, totalGB - freeGB)
                    let percent = (usedGB / totalGB) * 100.0
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.storageTotalGB = totalGB
                        self.storageUsedGB = usedGB
                        self.storageFreeGB = freeGB
                        self.storageUsedPercent = min(100.0, max(0.0, percent))
                    }
                }
            } catch {
                print("Erro ao ler dados de armazenamento: \(error)")
            }
        }
    }
    
    // Quick Actions
    func lockScreen() {
        let script = "tell application \"System Events\" to keystroke \"q\" using {command down, control down}"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
    
    func emptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
    
    func sleepMac() {
        let script = "tell application \"Finder\" to sleep"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
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
    }

    func clearTray() {
        trayItems.removeAll()
        saveTray()
    }

    /// Lê as URLs de arquivo dos providers de um drop.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else if let u = item as? NSURL { url = u as URL }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.addToTray(urls) }
        return true
    }
}
