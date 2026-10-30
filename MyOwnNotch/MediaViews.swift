//
//  MediaViews.swift
//  MyOwnNotch
//
//  Views do módulo de controle de mídia (compact e expanded).
//

import SwiftUI

// MARK: - Compact Media

struct MediaCompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            Image(systemName: vm.mediaIsPlaying ? "music.note" : "pause.fill")
                .font(NotchFont.label.weight(.medium))
                .foregroundStyle(NotchTheme.textSecondary)
                .contentTransition(.symbolEffect(.replace))

            MarqueeText(text: vm.mediaTitle, font: .system(size: 11, weight: .medium), color: .white)
                .frame(maxWidth: 140)

            if vm.mediaIsPlaying {
                AudioBarsView(bars: vm.audioBars, color: NotchTheme.textTertiary, barWidth: 2.5, maxHeight: 12)
                    .frame(width: 22)
            }
        }
    }
}

// MARK: - Expanded Media

struct MediaExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    enum Panel { case queue, devices }
    @State private var panel: Panel?

    var body: some View {
        if vm.automationDenied {
            StateView(kind: .noPermission,
                      message: "Permita o controle do Spotify/Música",
                      actionTitle: "Abrir Ajustes") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.mediaSource.isEmpty {
            MediaEmptyView()
        } else if panel == .queue && vm.mediaSource == "Spotify" {
            SpotifyPanelView(spotify: vm.spotify) { withAnimation(Motion.micro) { panel = nil } }
        } else if panel == .devices {
            DevicePanelView(spotify: vm.spotify,
                            onClose: { withAnimation(Motion.micro) { panel = nil } },
                            onConnect: { withAnimation(Motion.micro) { panel = .queue } })
        } else {
            VStack(spacing: NotchTheme.Spacing.m) {
                // Capa + título + onda sonora
                HStack(spacing: 12) {
                    AlbumArtView(artwork: vm.mediaArtwork, isPlaying: vm.mediaIsPlaying)
                        .frame(width: 58, height: 58)
                        .onTapGesture { vm.openMediaApp() }
                        .accessibilityLabel("Capa do álbum")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { vm.openMediaApp() }
                        .help("Abrir \(vm.mediaSource == "Music" ? "Apple Music" : "Spotify")")

                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: vm.mediaTitle,
                                    font: NotchFont.title.weight(.bold), color: .white)
                            .frame(height: 18)
                        Text(vm.mediaArtist.isEmpty ? "Artista desconhecido" : vm.mediaArtist)
                            .font(NotchFont.body.weight(.medium))
                            .foregroundStyle(NotchTheme.textTertiary)
                            .lineLimit(1)
                        if !vm.mediaAlbum.isEmpty {
                            Text(vm.mediaAlbum)
                                .font(NotchFont.caption)
                                .foregroundStyle(NotchTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)

                    if vm.mediaIsPlaying {
                        AudioBarsView(bars: vm.audioBars, color: .green.opacity(0.85), barWidth: 3, maxHeight: 22)
                            .frame(width: 30)
                    }
                }

                MediaProgressBar()

                // Controles
                HStack(spacing: 0) {
                    if vm.mediaSource == "Spotify" {
                        ToggleIcon(icon: "list.bullet", label: "Fila de reprodução", active: vm.spotify.isConnected) {
                            withAnimation(Motion.micro) { panel = .queue }
                        }
                    }
                    ToggleIcon(icon: "shuffle", label: vm.mediaShuffle ? "Desativar aleatório" : "Ativar aleatório", active: vm.mediaShuffle) { vm.mediaToggleShuffle() }
                    Spacer()
                    MediaButton(icon: "backward.fill", label: "Anterior", size: 16) { vm.mediaPrevious() }
                    Spacer().frame(width: 26)
                    MediaButton(icon: vm.mediaIsPlaying ? "pause.fill" : "play.fill", label: vm.mediaIsPlaying ? "Pausar" : "Reproduzir", size: 22) { vm.mediaPlayPause() }
                        .frame(width: 34, height: 34)
                    Spacer().frame(width: 26)
                    MediaButton(icon: "forward.fill", label: "Próxima", size: 16) { vm.mediaNext() }
                    Spacer()
                    if vm.mediaSource == "Spotify" && vm.spotify.isConnected {
                        LikeButton(spotify: vm.spotify)
                    }
                    ToggleIcon(icon: "laptopcomputer.and.iphone", label: "Dispositivos", active: false) {
                        withAnimation(Motion.micro) { panel = .devices }
                    }
                    ToggleIcon(icon: vm.mediaRepeat == .one ? "repeat.1" : "repeat",
                               label: vm.mediaRepeat == .off ? "Repetir: desligado" : (vm.mediaRepeat == .one ? "Repetir: faixa" : "Repetir: tudo"),
                               active: vm.mediaRepeat != .off) { vm.mediaCycleRepeat() }
                }
            }
        }
    }
}

/// Estado sem player: atalhos para abrir Spotify / Apple Music
struct MediaEmptyView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        VStack(spacing: NotchTheme.Spacing.l) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NotchTheme.textTertiary)
                .accessibilityHidden(true)
            Text("Nenhuma música tocando")
                .font(NotchFont.body.weight(.medium))
                .foregroundStyle(NotchTheme.textSecondary)
            HStack(spacing: NotchTheme.Spacing.m) {
                openButton("Spotify", color: .green) { vm.openMediaApp("Spotify") }
                openButton("Apple Music", color: .pink) { vm.openMediaApp("Music") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func openButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Abrir \(title)").font(NotchFont.label.weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.15)))
        }
        .buttonStyle(HoverPressStyle())
        .accessibilityLabel("Abrir \(title)")
    }
}

/// Estilo de botão com hover (realce) e press (escala) para controles do notch.
struct HoverPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        HoverPressBody(configuration: configuration, pressedScale: pressedScale)
    }
    private struct HoverPressBody: View {
        let configuration: Configuration
        let pressedScale: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .brightness(hovering ? 0.15 : 0)
                .scaleEffect(configuration.isPressed ? pressedScale : 1)
                .motionAnimation(Motion.micro, value: configuration.isPressed)
                .motionAnimation(Motion.micro, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

struct LikeButton: View {
    @ObservedObject var spotify: SpotifyService
    var body: some View {
        Button { spotify.toggleLike() } label: {
            Image(systemName: spotify.apiError != nil ? "heart.slash" : (spotify.isLiked ? "heart.fill" : "heart"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(spotify.apiError != nil ? Color.orange : (spotify.isLiked ? Color.green : NotchTheme.textTertiary))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(HoverPressStyle())
        .accessibilityLabel(spotify.isLiked ? "Remover das curtidas" : "Curtir")
        .help(spotify.apiError ?? (spotify.isLiked ? "Remover das curtidas" : "Curtir"))
    }
}

struct ToggleIcon: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.green : NotchTheme.textTertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(label)
    }
}

/// Barra de progresso com tempo decorrido/restante; arraste para buscar na faixa.
struct MediaProgressBar: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var hovering = false

    private func fmt(_ t: Double) -> String {
        let s = Int(max(0, t)); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            Text(fmt(vm.mediaPosition))
                .frame(width: 34, alignment: .trailing)
            GeometryReader { geo in
                let progress = vm.mediaDuration > 0 ? CGFloat(vm.mediaPosition / vm.mediaDuration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchTheme.fillSelected)
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * min(1, progress)))
                    Circle().fill(Color.white)
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, geo.size.width * min(1, progress) - 4.5))
                        .opacity(hovering || vm.isScrubbingMedia ? 1 : 0)
                }
                .frame(height: hovering || vm.isScrubbingMedia ? 5 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard vm.mediaDuration > 0 else { return }
                            vm.isScrubbingMedia = true
                            vm.mediaPosition = vm.mediaDuration * Double(min(1, max(0, g.location.x / geo.size.width)))
                        }
                        .onEnded { g in
                            guard vm.mediaDuration > 0 else { vm.isScrubbingMedia = false; return }
                            let target = vm.mediaDuration * Double(min(1, max(0, g.location.x / geo.size.width)))
                            vm.mediaSeek(to: target)
                            vm.isScrubbingMedia = false
                        }
                )
                .onHover { hovering = $0 }
                .motionAnimation(Motion.micro, value: hovering)
            }
            .frame(height: 14)
            .accessibilityElement()
            .accessibilityLabel("Progresso da faixa")
            .accessibilityValue("\(fmt(vm.mediaPosition)) de \(fmt(vm.mediaDuration))")
            .accessibilityAdjustableAction { dir in
                guard vm.mediaDuration > 0 else { return }
                let delta = dir == .increment ? 10.0 : -10.0
                vm.mediaSeek(to: min(vm.mediaDuration, max(0, vm.mediaPosition + delta)))
            }
            Text("-" + fmt(vm.mediaDuration - vm.mediaPosition))
                .frame(width: 38, alignment: .leading)
        }
        .font(NotchFont.caption.weight(.medium).monospaced())
        .foregroundStyle(NotchTheme.textTertiary)
    }
}

// MARK: - Album Art View

struct AlbumArtView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let image = artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous))
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(hue: 0.75, saturation: 0.6, brightness: 0.25),
                                 Color(hue: 0.85, saturation: 0.7, brightness: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(NotchTheme.textTertiary)
                }
                .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous))
            }
        }
        .scaleEffect(isPlaying || reduceMotion ? 1.0 : 0.92)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        .motionAnimation(Motion.content, value: isPlaying)
    }
}

// MARK: - Botão de Controle

struct MediaButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverPressStyle(pressedScale: 0.8))
        .accessibilityLabel(label)
        .help(label)
    }
}
