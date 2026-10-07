//
//  ContentView.swift
//  MyOwnNotch
//
//  Este arquivo não é mais usado como view principal.
//  O app usa uma janela NSPanel flutuante gerenciada pelo AppDelegate.
//  Mantido apenas para compatibilidade com Xcode Previews.
//

import SwiftUI

// Preview de demonstração do Notch
#Preview {
    NotchIslandView()
        .environmentObject(NotchViewModel())
        .frame(width: 380, height: 160)
        .background(Color.gray.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}
