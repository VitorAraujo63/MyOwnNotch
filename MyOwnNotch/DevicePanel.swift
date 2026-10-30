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
        VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
            // Cabeçalho + volume do player
            HStack(spacing: NotchTheme.Spacing.s) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(NotchFont.caption.weight(.bold)).foregroundStyle(NotchTheme.textTertiary)
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(HoverPressStyle())
                .accessibilityLabel("Voltar")
                .help("Voltar")
                Text("Dispositivos").font(NotchFont.label.weight(.semibold)).foregroundStyle(NotchTheme.textSecondary)
                Spacer()
                Image(systemName: vm.mediaVolume < 1 ? "speaker.slash.fill" : (vm.mediaVolume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).frame(width: 16)
                    .accessibilityHidden(true)
                VolumeSlider(value: Binding(get: { vm.mediaVolume }, set: { vm.setMediaVolume($0) }))
                    .frame(width: 110, height: 14)
            }

            HStack(alignment: .top, spacing: NotchTheme.Spacing.l) {
                column(title: "Saída do Mac") {
                    ForEach(audio.outputs) { out in
                        DeviceRow(icon: out.icon, title: out.name, subtitle: nil, active: out.isDefault) { audio.select(out) }
                    }
                }
                Rectangle().fill(NotchTheme.fillSubtle).frame(width: 0.5)
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
            VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
                Text("Entre no Spotify para trocar o dispositivo de reprodução (celular, caixas, outros PCs).")
                    .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).fixedSize(horizontal: false, vertical: true)
                Button(action: onConnect) {
                    Text("Conectar").font(NotchFont.caption.weight(.bold)).foregroundStyle(Color.black)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(deviceGreen))
                }
                .buttonStyle(HoverPressStyle(pressedScale: 0.95))
                .accessibilityLabel("Conectar ao Spotify")
            }
        } else if let err = spotify.apiError {
            StateView(kind: .failed(err), actionTitle: "Tentar de novo") {
                Task { await spotify.refreshDevices() }
            }
        } else if spotify.devices.isEmpty {
            Text("Nenhum dispositivo ativo. Abra o Spotify em algum aparelho.")
                .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
        } else {
            ForEach(spotify.devices) { dev in
                DeviceRow(icon: dev.icon, title: dev.name, subtitle: dev.isThisMac ? "Este Mac" : dev.type,
                          active: dev.isActive) { spotify.transfer(to: dev) }
            }
        }
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(NotchFont.caption.weight(.bold)).foregroundStyle(NotchTheme.textTertiary)
                .accessibilityAddTraits(.isHeader)
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
                Image(systemName: icon).font(NotchFont.label.weight(.semibold))
                    .foregroundStyle(active ? deviceGreen : NotchTheme.textSecondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(NotchFont.label.weight(active ? .bold : .medium))
                        .foregroundStyle(active ? deviceGreen : NotchTheme.textPrimary).lineLimit(1)
                    if let subtitle { Text(subtitle).font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if active { Image(systemName: "checkmark").font(NotchFont.caption.weight(.bold)).foregroundStyle(deviceGreen) }
            }
            .padding(.horizontal, NotchTheme.Spacing.s).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.medium)
                .fill(hovering ? NotchTheme.fillSelected : (active ? NotchTheme.fillSubtle : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(active ? "Ativo" : "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct VolumeSlider: View {
    @Binding var value: Double   // 0...100
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NotchTheme.fillSelected).frame(height: hovering ? 5 : 4)
                Capsule().fill(NotchTheme.textPrimary.opacity(0.9))
                    .frame(width: max(0, geo.size.width * CGFloat(value / 100)), height: hovering ? 5 : 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .motionAnimation(Motion.micro, value: hovering)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(min(1, max(0, g.location.x / geo.size.width))) * 100
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value)) por cento")
        .accessibilityAdjustableAction { dir in
            value = min(100, max(0, value + (dir == .increment ? 5 : -5)))
        }
    }
}
