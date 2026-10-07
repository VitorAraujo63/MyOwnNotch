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
        // A Settings scene opcional (pode ser expandida no futuro)
        Settings {
            EmptyView()
        }
    }
}
