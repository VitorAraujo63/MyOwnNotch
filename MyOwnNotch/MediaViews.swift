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
        HStack(spacing: 8) {
            Image(systemName: vm.mediaIsPlaying ? "music.note" : "pause.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .contentTransition(.symbolEffect(.replace))

            MarqueeText(text: vm.mediaTitle, font: .system(size: 11, weight: .medium), color: .white)
                .frame(maxWidth: 140)

            if vm.mediaIsPlaying {
                AudioBarsView(bars: vm.audioBars, color: .white.opacity(0.6), barWidth: 2.5, maxHeight: 12)
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
        if vm.mediaSource.isEmpty {
            MediaEmptyView()
        } else if panel == .queue && vm.mediaSource == "Spotify" {
            SpotifyPanelView(spotify: vm.spotify) { withAnimation(.easeOut(duration: 0.15)) { panel = nil } }
        } else if panel == .devices {
            DevicePanelView(spotify: vm.spotify,
                            onClose: { withAnimation(.easeOut(duration: 0.15)) { panel = nil } },
                            onConnect: { withAnimation(.easeOut(duration: 0.15)) { panel = .queue } })
        } else {
            VStack(spacing: 8) {
                // Capa + título + onda sonora
                HStack(spacing: 12) {
                    AlbumArtView(artwork: vm.mediaArtwork, isPlaying: vm.mediaIsPlaying)
                        .frame(width: 58, height: 58)
                        .onTapGesture { vm.openMediaApp() }
                        .help("Abrir \(vm.mediaSource == "Music" ? "Apple Music" : "Spotify")")

                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: vm.mediaTitle,
                                    font: .system(size: 14, weight: .bold), color: .white)
                            .frame(height: 18)
                        Text(vm.mediaArtist.isEmpty ? "Artista desconhecido" : vm.mediaArtist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                        if !vm.mediaAlbum.isEmpty {
                            Text(vm.mediaAlbum)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
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
                        ToggleIcon(icon: "list.bullet", active: vm.spotify.isConnected) {
                            withAnimation(.easeOut(duration: 0.15)) { panel = .queue }
                        }
                    }
                    ToggleIcon(icon: "shuffle", active: vm.mediaShuffle) { vm.mediaToggleShuffle() }
                    Spacer()
                    MediaButton(icon: "backward.fill", size: 16) { vm.mediaPrevious() }
                    Spacer().frame(width: 26)
                    MediaButton(icon: vm.mediaIsPlaying ? "pause.fill" : "play.fill", size: 22) { vm.mediaPlayPause() }
                        .frame(width: 34, height: 34)
                    Spacer().frame(width: 26)
                    MediaButton(icon: "forward.fill", size: 16) { vm.mediaNext() }
                    Spacer()
                    if vm.mediaSource == "Spotify" && vm.spotify.isConnected {
                        LikeButton(spotify: vm.spotify)
                    }
                    ToggleIcon(icon: "laptopcomputer.and.iphone", active: false) {
                        withAnimation(.easeOut(duration: 0.15)) { panel = .devices }
                    }
                    ToggleIcon(icon: vm.mediaRepeat == .one ? "repeat.1" : "repeat", active: vm.mediaRepeat != .off) { vm.mediaCycleRepeat() }
                }
            }
        }
    }
}

/// Estado sem player: atalhos para abrir Spotify / Apple Music
struct MediaEmptyView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 26, weight: .light)).foregroundColor(.white.opacity(0.4))
            Text("Nenhuma música tocando").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.6))
            HStack(spacing: 8) {
                openButton("Spotify", color: .green) { vm.openMediaApp("Spotify") }
                openButton("Apple Music", color: .pink) { vm.openMediaApp("Music") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func openButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Abrir \(title)").font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}

struct LikeButton: View {
    @ObservedObject var spotify: SpotifyService
    var body: some View {
        Button { spotify.toggleLike() } label: {
            Image(systemName: spotify.apiError != nil ? "heart.slash" : (spotify.isLiked ? "heart.fill" : "heart"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(spotify.apiError != nil ? .orange : (spotify.isLiked ? .green : .white.opacity(0.4)))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(spotify.apiError ?? (spotify.isLiked ? "Remover das curtidas" : "Curtir"))
    }
}

struct ToggleIcon: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(active ? .green : .white.opacity(0.4))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
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
        HStack(spacing: 8) {
            Text(fmt(vm.mediaPosition))
                .frame(width: 34, alignment: .trailing)
            GeometryReader { geo in
                let progress = vm.mediaDuration > 0 ? CGFloat(vm.mediaPosition / vm.mediaDuration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
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
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(height: 14)
            Text("-" + fmt(vm.mediaDuration - vm.mediaPosition))
                .frame(width: 38, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Album Art View

struct AlbumArtView: View {
    let artwork: NSImage?
    let isPlaying: Bool

    var body: some View {
        ZStack {
            if let image = artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(hue: 0.75, saturation: 0.6, brightness: 0.25),
                                 Color(hue: 0.85, saturation: 0.7, brightness: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .scaleEffect(isPlaying ? 1.0 : 0.92)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: isPlaying)
    }
}

// MARK: - Botão de Controle

struct MediaButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isPressed = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { isPressed = false }
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .scaleEffect(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
