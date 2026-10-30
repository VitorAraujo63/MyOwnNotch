//
//  SettingsView.swift
//  MyOwnNotch
//
//  Janela de Ajustes (aberta pelo menu da barra).
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(SettingsKey.showLiveActivities) private var showLiveActivities = true
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKey.showVolumeHUD) private var showVolumeHUD = true
    @State private var hiddenTick = 0   // re-renderiza ao mudar módulos ocultos
    @AppStorage(SettingsKey.timerFocusMinutes) private var focusMinutes = 25
    @AppStorage(SettingsKey.timerBreakMinutes) private var breakMinutes = 5
    @AppStorage(SettingsKey.timerSoundEnabled) private var timerSound = true
    @AppStorage(SettingsKey.weatherLocation) private var weatherLocation = ""
    @AppStorage(SettingsKey.calendarEnabled) private var calendarEnabled = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    private static let modules: [(NotchModule, String)] = [
        (.media, "Música"), (.battery, "Bateria"), (.weather, "Clima"),
        (.systemMonitor, "Monitor do sistema"), (.agent, "Claude"), (.github, "GitHub"),
        (.tray, "Bandeja de arquivos"), (.crypto, "Crypto"), (.terminal, "Terminal"),
        (.timer, "Timer"), (.calendar, "Calendário")
    ]

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Mostrar atividades ao vivo nas laterais", isOn: $showLiveActivities)
                Toggle("Mostrar HUD de volume", isOn: $showVolumeHUD)
                Toggle("Mostrar ícone na barra de menus", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("O app continua rodando. Para reabrir os Ajustes, abra o MyOwnNotch novamente (Spotlight ou Launchpad).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Módulos") {
                ForEach(Self.modules, id: \.0.storageKey) { module, name in
                    Toggle(name, isOn: binding(for: module))
                }
            }

            Section("Timer") {
                Stepper("Foco: \(focusMinutes) min", value: $focusMinutes, in: 1...180)
                Stepper("Pausa: \(breakMinutes) min", value: $breakMinutes, in: 1...60)
                Toggle("Tocar som ao terminar", isOn: $timerSound)
            }

            Section("Clima") {
                TextField("Local padrão", text: $weatherLocation, prompt: Text("Automático"))
                Text("Deixe vazio para usar a localização automática.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calendário") {
                Toggle("Mostrar próxima reunião", isOn: $calendarEnabled)
                Text("Ao ativar, o macOS pedirá permissão para acessar seus calendários.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 580)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: Helpers

    /// Módulos ocultos ficam como [String] (JSON em Data via RawRepresentable não é necessário aqui:
    /// lemos/gravamos direto no UserDefaults para manter o formato [String] do contrato).
    private func hiddenSet() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: SettingsKey.hiddenModules) ?? [])
    }

    private func binding(for module: NotchModule) -> Binding<Bool> {
        Binding(
            get: { _ = hiddenTick; return !hiddenSet().contains(module.storageKey) },
            set: { visible in
                var set = hiddenSet()
                if visible { set.remove(module.storageKey) } else { set.insert(module.storageKey) }
                UserDefaults.standard.set(set.sorted(), forKey: SettingsKey.hiddenModules)
                hiddenTick += 1
            }
        )
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Não foi possível alterar: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        UserDefaults.standard.set(launchAtLogin, forKey: SettingsKey.launchAtLogin)
    }
}
