//
//  SpotifyViews.swift
//  MyOwnNotch
//
//  Painel de conexão e fila "Playing Next" do Spotify.
//

import SwiftUI

private let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

/// Conteúdo alternativo do player: fila (conectado) ou painel de conexão.
struct SpotifyPanelView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var spotify: SpotifyService
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
            HStack(spacing: NotchTheme.Spacing.s) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(NotchFont.caption.weight(.bold)).foregroundStyle(NotchTheme.textTertiary)
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(HoverPressStyle())
                .accessibilityLabel("Voltar")
                .help("Voltar")
                Text(spotify.isConnected ? "A seguir" : "Conectar ao Spotify")
                    .font(NotchFont.label.weight(.semibold)).foregroundStyle(NotchTheme.textSecondary)
                Spacer()
                if spotify.isConnected {
                    Button("Desconectar") { spotify.disconnect(); onClose() }
                        .buttonStyle(HoverPressStyle(pressedScale: 0.95))
                        .font(NotchFont.caption.weight(.medium)).foregroundStyle(NotchTheme.textTertiary)
                        .accessibilityHint("Encerra a conexão com a conta do Spotify")
                }
            }
            if spotify.isConnected { queueList } else { connectForm }
        }
        .onAppear { if spotify.isConnected { Task { await spotify.refreshQueue() } } }
    }

    // MARK: Fila

    private var queueList: some View {
        VStack(spacing: NotchTheme.Spacing.xs) {
            if let err = spotify.apiError {
                StateView(kind: .failed(err), actionTitle: "Tentar de novo") {
                    Task { await spotify.refreshQueue() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if spotify.queue.isEmpty {
                StateView(kind: .failed("Fila vazia ou nenhum dispositivo ativo"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(spotify.queue.enumerated()), id: \.element.id) { index, item in
                            QueueRow(item: item) { vm.mediaSkip(times: index + 1) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Conexão

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
            Text("Para ver a fila e curtir faixas: crie um app em developer.spotify.com/dashboard, adicione o Redirect URI abaixo e cole o Client ID.")
                .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: NotchTheme.Spacing.s) {
                Text(SpotifyService.redirectURI)
                    .font(NotchFont.caption.monospaced()).foregroundStyle(NotchTheme.textSecondary).textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SpotifyService.redirectURI, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary) }
                .buttonStyle(HoverPressStyle())
                .accessibilityLabel("Copiar Redirect URI")
                .help("Copiar Redirect URI")
                Spacer()
            }
            .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, NotchTheme.Spacing.xs)
            .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.small).fill(NotchTheme.fillSubtle))

            HStack(spacing: NotchTheme.Spacing.s) {
                TextField("Client ID", text: $spotify.clientID)
                    .textFieldStyle(.plain).font(NotchFont.label.monospaced()).foregroundStyle(NotchTheme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(NotchTheme.fillSubtle))
                    .onSubmit { spotify.connect() }
                    .accessibilityLabel("Client ID do Spotify")
                Button { spotify.connect() } label: {
                    HStack(spacing: NotchTheme.Spacing.xs) {
                        if spotify.isConnecting { ProgressView().controlSize(.mini).scaleEffect(0.6) }
                        Text(spotify.isConnecting ? "Aguardando…" : "Conectar").font(NotchFont.label.weight(.bold))
                    }
                    .foregroundStyle(Color.black).padding(.horizontal, NotchTheme.Spacing.l).padding(.vertical, 5)
                    .background(Capsule().fill(spotifyGreen))
                }
                .buttonStyle(HoverPressStyle(pressedScale: 0.95)).disabled(spotify.isConnecting)
            }
            if let err = spotify.errorMessage {
                StateView(kind: .failed(err))
            }
        }
    }
}

struct QueueRow: View {
    let item: SpotifyQueueItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: NotchTheme.Spacing.m) {
                AsyncImage(url: item.artworkURL) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { NotchTheme.fillSelected }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).font(NotchFont.label.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                    Text(item.artist).font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).lineLimit(1)
                }
                Spacer()
                if hovering { Image(systemName: "play.fill").font(NotchFont.caption).foregroundStyle(spotifyGreen) }
            }
            .padding(.horizontal, NotchTheme.Spacing.s).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.medium).fill(hovering ? NotchTheme.fillSubtle : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(item.name), \(item.artist)")
        .accessibilityHint("Pula para esta faixa")
    }
}
