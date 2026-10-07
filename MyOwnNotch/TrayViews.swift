//
//  TrayViews.swift
//  MyOwnNotch
//
//  Bandeja ("shelf") de arquivos: solte arquivos no notch para guardá-los
//  temporariamente e arraste-os de volta para qualquer outro lugar.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

struct TrayItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

// MARK: - Expanded

struct TrayExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cyan)
                Text(vm.trayItems.isEmpty ? "Bandeja" : "Bandeja · \(vm.trayItems.count) \(vm.trayItems.count == 1 ? "item" : "itens")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                if !vm.trayItems.isEmpty {
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.clearTray() } } label: {
                        Text("Limpar")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                if vm.trayItems.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 22, weight: .light))
                        Text("Solte arquivos aqui para guardá-los")
                            .font(.system(size: 11, weight: .medium))
                        Text("Depois arraste para qualquer lugar")
                            .font(.system(size: 9))
                            .opacity(0.6)
                    }
                    .foregroundColor(.white.opacity(0.55))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.trayItems) { item in
                                TrayTile(item: item)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vm.isDropTargeted ? Color.cyan.opacity(0.14) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(vm.isDropTargeted ? Color.cyan : Color.white.opacity(0.14),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .animation(.easeOut(duration: 0.15), value: vm.isDropTargeted)
        }
    }
}

// MARK: - Tile

struct TrayTile: View {
    @EnvironmentObject var vm: NotchViewModel
    let item: TrayItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                TrayThumbnail(url: item.url)
                    .frame(width: 46, height: 46)
                    .opacity(item.exists ? 1 : 0.35)

                if hovering {
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.removeFromTray(item) } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.black.opacity(0.75)).overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 52, height: 50)

            Text(item.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        // Arrastar para fora: entrega o arquivo real para o destino (Finder, Mail, apps…)
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(item.url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copiar caminho") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Remover da bandeja") { vm.removeFromTray(item) }
        }
        .help(item.url.path)
    }
}

struct TrayThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .task(id: url) {
                let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 92, height: 92),
                                                       scale: 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                    image = rep.nsImage
                }
            }
    }
}

// MARK: - Compact

struct TrayCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 12)).foregroundColor(.cyan)
            Text("\(vm.trayItems.count) \(vm.trayItems.count == 1 ? "arquivo" : "arquivos")")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
    }
}
