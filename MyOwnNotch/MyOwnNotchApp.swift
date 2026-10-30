//
//  MyOwnNotchApp.swift
//  MyOwnNotch
//
//  Created by Vitor H on 28/09/26.
//

import SwiftUI
import AppKit

@main
struct MyOwnNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A cena Settings existe só porque o App exige uma cena. O ⌘, padrão dela abriria uma
        // janela vazia; o comando é substituído para abrir a mesma janela de Ajustes do menu.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ajustes…") { appDelegate.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
