//
//  Contracts.swift
//  MyOwnNotch
//
//  Tipos compartilhados entre serviços e views. Mudanças aqui afetam
//  vários módulos — altere com cuidado.
//

import Foundation

// MARK: - Estado de carregamento

/// Estado genérico para módulos que dependem de rede ou permissão.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case offline
    case noPermission
    case failed(String)
}

// MARK: - Live Activities

/// Atividades "ao vivo" que podem ocupar as laterais do notch no estado idle.
/// A ordem dos casos define a prioridade (primeiro = mais importante).
enum LiveActivity: Int, Comparable, CaseIterable, Identifiable {
    case privacy = 0   // câmera ou microfone em uso
    case timerEnding   // timer rodando com < 60 s
    case meeting       // reunião começando em até 10 min ou em andamento
    case capsLock      // Caps Lock ligado
    case timer         // timer rodando
    case media         // música tocando
    case charging      // carregando
    case stayAwake     // "Manter acordado" ativo (IOPMAssertion)

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Módulo aberto ao clicar na atividade.
    var module: NotchModule {
        switch self {
        case .privacy:              return .systemMonitor
        case .timerEnding, .timer:  return .timer
        case .meeting:              return .calendar
        case .media:                return .media
        case .charging:             return .battery
        case .capsLock:             return .none     // só indicador; clique abre o módulo padrão
        case .stayAwake:            return .battery
        }
    }
}

// MARK: - Calendário

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    /// Link de videochamada detectado (Meet, Zoom, Teams, FaceTime, Webex).
    let joinURL: URL?
    /// Cor do calendário em hex "#RRGGBB".
    let colorHex: String?
}

// MARK: - Ajustes (chaves de UserDefaults)

enum SettingsKey {
    static let launchAtLogin      = "settings.launchAtLogin"       // Bool
    static let hiddenModules      = "settings.hiddenModules"       // [String] (NotchModule.storageKey)
    static let weatherLocation    = "settings.weatherLocation"     // String ("" = automático)
    static let timerFocusMinutes  = "settings.timerFocusMinutes"   // Int
    static let timerBreakMinutes  = "settings.timerBreakMinutes"   // Int
    static let timerSoundEnabled  = "settings.timerSoundEnabled"   // Bool
    static let showLiveActivities = "settings.showLiveActivities"  // Bool (padrão true)
    static let showVolumeHUD      = "settings.showVolumeHUD"       // Bool (padrão true)
    static let calendarEnabled    = "settings.calendarEnabled"     // Bool (padrão false, pede permissão)
    static let showMenuBarIcon    = "settings.showMenuBarIcon"     // Bool (padrão true)
    static let agentModeAcknowledged = "settings.agentModeAcknowledged" // Bool
    // Identidade visual (estilo Droppy)
    static let surfaceStyle       = "settings.surfaceStyle"        // String (SurfaceStyle.rawValue, padrão dynamicGlass)
    static let accentChoice       = "settings.accentChoice"        // String (AccentChoice.rawValue, padrão module)
    static let solidOnLowPower    = "settings.solidOnLowPower"     // Bool (padrão true)
    // Novas features
    static let clipboardEnabled   = "settings.clipboardEnabled"    // Bool (padrão true)
    static let swipeToSkipTrack   = "settings.swipeToSkipTrack"    // Bool (padrão true) — swipe de 2 dedos no notch recolhido
    static let showCapsLock       = "settings.showCapsLock"        // Bool (padrão true)
}

// MARK: - Aparência

/// Material da ilha. `dynamicGlass`: preto na câmera derretendo em vidro; `liquidGlass`: vidro
/// claro do topo ao fim; `black`: sólido (também usado automaticamente em Modo de Pouca Energia).
enum SurfaceStyle: String, CaseIterable, Identifiable {
    case dynamicGlass, liquidGlass, black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dynamicGlass: return "Dynamic Glass"
        case .liquidGlass:  return "Liquid Glass"
        case .black:        return "Preto"
        }
    }
}

/// Cor de destaque. `module` usa a cor de cada módulo (NotchTheme.accent(for:)).
enum AccentChoice: String, CaseIterable, Identifiable {
    case module, blue, purple, pink, orange, green, mint, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .module: return "Por módulo"
        case .blue:   return "Azul"
        case .purple: return "Roxo"
        case .pink:   return "Rosa"
        case .orange: return "Laranja"
        case .green:  return "Verde"
        case .mint:   return "Menta"
        case .white:  return "Branco"
        }
    }
}

// MARK: - Clipboard

/// Item do histórico da área de transferência. Mantido só em memória.
struct ClipboardItem: Identifiable, Equatable {
    enum Kind: Equatable { case text, link, color, image, file }
    let id: UUID
    let kind: Kind
    /// Texto, URL, hex da cor ou caminho do arquivo (para .image pode ser nil).
    let text: String?
    /// PNG reduzido (thumbnail, máx. ~160 px) para `.image`.
    let imagePNG: Data?
    /// Nome do app de onde veio (frontmost no momento da cópia), se conhecido.
    let sourceApp: String?
    let date: Date
    var isPinned: Bool
}

extension NotchModule {
    /// Identificador estável para persistência.
    var storageKey: String {
        switch self {
        case .none: return "none"
        case .media: return "media"
        case .battery: return "battery"
        case .timer: return "timer"
        case .systemMonitor: return "systemMonitor"
        case .weather: return "weather"
        case .actions: return "actions"
        case .volume: return "volume"
        case .terminal: return "terminal"
        case .crypto: return "crypto"
        case .tray: return "tray"
        case .agent: return "agent"
        case .github: return "github"
        case .calendar: return "calendar"
        case .clipboard: return "clipboard"
        }
    }
}
