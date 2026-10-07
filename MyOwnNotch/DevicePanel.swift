//
//  DevicePanel.swift
//  MyOwnNotch
//
//  Painel de dispositivos: saída de áudio do Mac + dispositivos Spotify Connect + volume.
//

import SwiftUI

private let deviceGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

struct DevicePanelView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var spotify: SpotifyService
    @StateObject private var audio = AudioOutputs()
    let onClose: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cabeçalho + volume do player
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text("Dispositivos").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                Spacer()
                Image(systemName: vm.mediaVolume < 1 ? "speaker.slash.fill" : (vm.mediaVolume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.5)).frame(width: 16)
                VolumeSlider(value: Binding(get: { vm.mediaVolume }, set: { vm.setMediaVolume($0) }))
                    .frame(width: 110, height: 14)
            }

            HStack(alignment: .top, spacing: 12) {
                column(title: "Saída do Mac") {
                    ForEach(audio.outputs) { out in
                        DeviceRow(icon: out.icon, title: out.name, subtitle: nil, active: out.isDefault) { audio.select(out) }
                    }
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 0.5)
                column(title: "Spotify Connect") { connectDevices }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            audio.refresh()
            vm.fetchMediaVolume()
            if spotify.isConnected { Task { await spotify.refreshDevices() } }
        }
    }

    @ViewBuilder private var connectDevices: some View {
        if !spotify.isConnected {
            VStack(alignment: .leading, spacing: 6) {
                Text("Entre no Spotify para trocar o dispositivo de reprodução (celular, caixas, outros PCs).")
                    .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                Button(action: onConnect) {
                    Text("Conectar").font(.system(size: 10, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(deviceGreen))
                }.buttonStyle(.plain)
            }
        } else if let err = spotify.apiError {
            Text(err).font(.system(size: 9.5)).foregroundColor(.orange.opacity(0.9))
        } else if spotify.devices.isEmpty {
            Text("Nenhum dispositivo ativo. Abra o Spotify em algum aparelho.")
                .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
        } else {
            ForEach(spotify.devices) { dev in
                DeviceRow(icon: dev.icon, title: dev.name, subtitle: dev.isThisMac ? "Este Mac" : dev.type,
                          active: dev.isActive) { spotify.transfer(to: dev) }
            }
        }
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).foregroundColor(.white.opacity(0.3))
            ScrollView(showsIndicators: false) { VStack(spacing: 2) { content() } }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct DeviceRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(active ? deviceGreen : .white.opacity(0.55)).frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 11, weight: active ? .bold : .medium))
                        .foregroundColor(active ? deviceGreen : .white.opacity(0.9)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 8.5)).foregroundColor(.white.opacity(0.4)).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if active { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(deviceGreen) }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.08 : (active ? 0.05 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct VolumeSlider: View {
    @Binding var value: Double   // 0...100

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: max(0, geo.size.width * CGFloat(value / 100)), height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(min(1, max(0, g.location.x / geo.size.width))) * 100
            })
        }
    }
}
