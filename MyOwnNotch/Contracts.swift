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
    case timer         // timer rodando
    case media         // música tocando
    case charging      // carregando

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
        }
    }
}
