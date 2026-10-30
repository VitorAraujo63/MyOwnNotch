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
        VStack(alignment: .leading, spacing: NotchTheme.Spacing.m) {
            HStack(spacing: NotchTheme.Spacing.s) {
                Image(systemName: "tray.full.fill")
                    .font(NotchFont.caption.weight(.semibold))
                    .foregroundStyle(Color.cyan)
                    .accessibilityHidden(true)
                Text(vm.trayItems.isEmpty ? "Bandeja" : "Bandeja · \(vm.trayItems.count) \(vm.trayItems.count == 1 ? "item" : "itens")")
                    .font(NotchFont.label.weight(.semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
                Spacer()
                if !vm.trayItems.isEmpty {
                    Button { withAnimation(Motion.snappy) { vm.clearTray() } } label: {
                        Text("Limpar")
                            .font(NotchFont.caption.weight(.semibold))
                            .foregroundStyle(NotchTheme.textSecondary)
                            .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, 3)
                            .background(Capsule().fill(NotchTheme.fillSelected))
                    }
                    .buttonStyle(HoverPressStyle(pressedScale: 0.95))
                    .accessibilityLabel("Limpar bandeja")
                    .help("Remover todos os itens da bandeja")
                }
            }

            ZStack {
                if vm.trayItems.isEmpty {
                    VStack(spacing: NotchTheme.Spacing.s) {
                        Image(systemName: vm.isDropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                            .font(.system(size: 22, weight: .light))
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                        Text(vm.isDropTargeted ? "Solte para guardar" : "Solte arquivos aqui para guardá-los")
                            .font(NotchFont.label.weight(.medium))
                        Text("Depois arraste para qualquer lugar")
                            .font(NotchFont.caption)
                    }
                    .foregroundStyle(vm.isDropTargeted ? Color.cyan : NotchTheme.textTertiary)
                    .accessibilityElement(children: .combine)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NotchTheme.Spacing.m) {
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
                RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
                    .fill(vm.isDropTargeted ? Color.cyan.opacity(0.14) : NotchTheme.fillSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
                    .strokeBorder(vm.isDropTargeted ? Color.cyan : NotchTheme.stroke,
                                  style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .motionAnimation(Motion.micro, value: vm.isDropTargeted)
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
                    Button { withAnimation(Motion.snappy) { vm.removeFromTray(item) } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.black.opacity(0.75)).overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5)))
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(HoverPressStyle())
                    .accessibilityLabel("Remover \(item.name) da bandeja")
                    .help("Remover da bandeja")
                    .offset(x: 5, y: -5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 52, height: 50)

            Text(item.name)
                .font(NotchFont.caption.weight(.medium))
                .foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.medium, style: .continuous).fill(hovering ? NotchTheme.fillSelected : Color.clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.micro) { hovering = h } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        // Arrastar para fora: entrega o arquivo real para o destino (Finder, Mail, apps…)
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(item.url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copiar caminho") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.resolvingSymlinksInPath().path, forType: .string)
            }
            Divider()
            Button("Remover da bandeja") { vm.removeFromTray(item) }
        }
        .help(item.url.resolvingSymlinksInPath().path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.exists ? item.name : "\(item.name), arquivo não encontrado")
        .accessibilityHint("Toque duas vezes para abrir. Use o menu de ações para mais opções.")
        .accessibilityAction(named: "Abrir") { NSWorkspace.shared.open(item.url) }
        .accessibilityAction(named: "Remover da bandeja") { vm.removeFromTray(item) }
    }
}

struct TrayThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.small, style: .continuous))
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
            Image(systemName: "tray.full.fill").font(NotchFont.body).foregroundStyle(Color.cyan)
            Text("\(vm.trayItems.count) \(vm.trayItems.count == 1 ? "arquivo" : "arquivos")")
                .font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
        }
    }
}
