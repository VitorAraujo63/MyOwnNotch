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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text(spotify.isConnected ? "Playing Next" : "Conectar ao Spotify")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                Spacer()
                if spotify.isConnected {
                    Button("Desconectar") { spotify.disconnect(); onClose() }
                        .buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.35))
                }
            }
            if spotify.isConnected { queueList } else { connectForm }
        }
        .onAppear { if spotify.isConnected { Task { await spotify.refreshQueue() } } }
    }

    // MARK: Fila

    private var queueList: some View {
        VStack(spacing: 4) {
            if let err = spotify.apiError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundColor(.orange)
                    Text(err).font(.system(size: 9.5)).foregroundColor(.orange.opacity(0.9)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if spotify.queue.isEmpty {
                Text("A fila está vazia ou nenhum dispositivo do Spotify está ativo.")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Para ver a fila e curtir faixas: crie um app em developer.spotify.com/dashboard, adicione o Redirect URI abaixo e cole o Client ID.")
                .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(SpotifyService.redirectURI)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.75)).textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SpotifyService.redirectURI, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 9)).foregroundColor(.white.opacity(0.5)) }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))

            HStack(spacing: 6) {
                TextField("Client ID", text: $spotify.clientID)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
                    .onSubmit { spotify.connect() }
                Button { spotify.connect() } label: {
                    HStack(spacing: 4) {
                        if spotify.isConnecting { ProgressView().controlSize(.mini).scaleEffect(0.6) }
                        Text(spotify.isConnecting ? "Aguardando…" : "Conectar").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.black).padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(spotifyGreen))
                }
                .buttonStyle(.plain).disabled(spotify.isConnecting)
            }
            if let err = spotify.errorMessage {
                Text(err).font(.system(size: 10)).foregroundColor(.orange)
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
            HStack(spacing: 8) {
                AsyncImage(url: item.artworkURL) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text(item.artist).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer()
                if hovering { Image(systemName: "play.fill").font(.system(size: 9)).foregroundColor(spotifyGreen) }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
