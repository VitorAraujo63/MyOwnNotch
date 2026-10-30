//
//  ClipboardViews.swift
//  MyOwnNotch
//
//  Histórico da área de transferência (só em memória): grade horizontal de cartões,
//  busca, fixar, remover e arrastar de volta para qualquer app.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Helpers

private extension ClipboardItem {
    var linkHost: String? {
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return url.host ?? text
    }

    /// Texto usado na busca e na prévia compacta.
    var previewText: String {
        switch kind {
        case .image: return "Imagem"
        case .file:  return text.map { ($0 as NSString).lastPathComponent } ?? "Arquivo"
        case .link:  return linkHost ?? text ?? "Link"
        case .text, .color: return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var kindLabel: String {
        switch kind {
        case .text:  return "Texto"
        case .link:  return "Link"
        case .color: return "Cor"
        case .image: return "Imagem"
        case .file:  return "Arquivo"
        }
    }

    var symbol: String {
        switch kind {
        case .text:  return "text.alignleft"
        case .link:  return "globe"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        case .file:  return "doc.fill"
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return previewText.localizedCaseInsensitiveContains(q)
            || (text?.localizedCaseInsensitiveContains(q) ?? false)
            || (sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
    }
}

// MARK: - Estado de busca / cache

/// Texto da busca, observável fora da view (o container desativa o Esc global enquanto há busca).
final class ClipboardSearchState: ObservableObject {
    static let shared = ClipboardSearchState()
    @Published var query = ""
    private init() {}
}

/// Imagens decodificadas uma vez por item (não decodificar PNG no body a cada render).
private enum ClipboardImageCache {
    private static let cache: NSCache<NSUUID, NSImage> = {
        let c = NSCache<NSUUID, NSImage>(); c.countLimit = 80; return c
    }()

    static func image(for item: ClipboardItem) -> NSImage? {
        let key = item.id as NSUUID
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = item.imagePNG, let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

// MARK: - Expanded

struct ClipboardExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View { ClipboardExpandedBody(clipboard: vm.clipboard) }
}

private struct ClipboardExpandedBody: View {
    @ObservedObject var clipboard: ClipboardService
    @AppStorage(SettingsKey.clipboardEnabled) private var enabled = true
    @ObservedObject private var search = ClipboardSearchState.shared
    private var query: String { search.query }
    @State private var copiedID: UUID?
    @State private var copiedResetTask: Task<Void, Never>?

    private var filtered: [ClipboardItem] {
        let list = clipboard.items.filter { $0.matches(query) }
        return list.filter(\.isPinned) + list.filter { !$0.isPinned }
    }

    private var hasUnpinned: Bool { clipboard.items.contains { !$0.isPinned } }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Spacing.m) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { copiedResetTask?.cancel(); search.query = "" }
    }

    private var header: some View {
        HStack(spacing: NotchTheme.Spacing.s) {
            Image(systemName: "list.clipboard.fill")
                .font(NotchFont.caption.weight(.semibold))
                .foregroundStyle(NotchTheme.accent(for: .clipboard))
                .accessibilityHidden(true)
            Text("Área de transferência")
                .font(NotchFont.label.weight(.semibold))
                .foregroundStyle(NotchTheme.textSecondary)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(NotchFont.caption)
                    .foregroundStyle(NotchTheme.textTertiary)
                    .accessibilityHidden(true)
                TextField("Buscar", text: $search.query)
                    .textFieldStyle(.plain)
                    .onExitCommand { search.query = "" }
                    .font(NotchFont.label)
                    .foregroundStyle(NotchTheme.textPrimary)
                    .accessibilityLabel("Buscar no histórico")
                if !query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(NotchFont.caption)
                            .foregroundStyle(NotchTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, 3)
            .frame(maxWidth: 180)
            .background(Capsule().fill(NotchTheme.fillSubtle))

            Spacer(minLength: 0)

            if hasUnpinned {
                Button { withAnimation(Motion.snappy) { clipboard.clearUnpinned() } } label: {
                    Text("Limpar")
                        .font(NotchFont.caption.weight(.semibold))
                        .foregroundStyle(NotchTheme.textSecondary)
                        .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, 3)
                        .background(Capsule().fill(NotchTheme.fillSelected))
                }
                .buttonStyle(HoverPressStyle(pressedScale: 0.95))
                .accessibilityLabel("Limpar itens não fixados")
                .help("Remover tudo, exceto os itens fixados")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !enabled && !clipboard.isRunning {
            placeholder(icon: "pause.circle", title: "Histórico desligado",
                        subtitle: "Ative em Ajustes > Geral > Histórico da área de transferência")
        } else if clipboard.items.isEmpty {
            placeholder(icon: "doc.on.clipboard", title: "Copie algo para começar",
                        subtitle: "Textos, links, cores, imagens e arquivos aparecem aqui")
        } else if filtered.isEmpty {
            placeholder(icon: "magnifyingglass", title: "Nada encontrado", subtitle: nil)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: NotchTheme.Spacing.m) {
                    ForEach(filtered) { item in
                        ClipboardCard(item: item, copied: copiedID == item.id,
                                      onCopy: { copy(item) },
                                      onPin: { withAnimation(Motion.snappy) { clipboard.togglePin(item.id) } },
                                      onRemove: { withAnimation(Motion.snappy) { clipboard.remove(item.id) } })
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }

    private func placeholder(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: NotchTheme.Spacing.s) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).accessibilityHidden(true)
            Text(title).font(NotchFont.label.weight(.medium))
            if let subtitle { Text(subtitle).font(NotchFont.caption).multilineTextAlignment(.center) }
        }
        .foregroundStyle(NotchTheme.textTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous).fill(NotchTheme.fillSubtle))
        .accessibilityElement(children: .combine)
    }

    private func copy(_ item: ClipboardItem) {
        clipboard.copyToPasteboard(item)
        withAnimation(Motion.micro) { copiedID = item.id }
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.micro) { copiedID = nil }
        }
    }
}

// MARK: - Cartão

private struct ClipboardCard: View {
    let item: ClipboardItem
    let copied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
                preview
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 44, alignment: .topLeading)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(caption)
                        .font(NotchFont.caption)
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(NotchTheme.accent(for: .clipboard))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(NotchTheme.Spacing.m)
            .frame(width: 128, height: 82)
            .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.medium, style: .continuous)
                .fill(hovering ? NotchTheme.fillSelected : NotchTheme.fillSubtle))
            .overlay {
                if copied {
                    RoundedRectangle(cornerRadius: NotchTheme.Radius.medium, style: .continuous)
                        .fill(Color.black.opacity(0.65))
                        .overlay {
                            Label("Copiado", systemImage: "checkmark")
                                .font(NotchFont.label.weight(.semibold))
                                .foregroundStyle(NotchTheme.textPrimary)
                        }
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.micro) { hovering = h } }
        .onDrag { provider }
        .contextMenu {
            Button(item.isPinned ? "Desafixar" : "Fixar", action: onPin)
            Button("Remover", role: .destructive, action: onRemove)
        }
        .help(item.sourceApp.map { "\(item.kindLabel) · \($0)" } ?? item.kindLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.previewText), \(caption)")
        .accessibilityHint("Toque para copiar de volta")
        .accessibilityAction(named: item.isPinned ? "Desafixar" : "Fixar", onPin)
        .accessibilityAction(named: "Remover", onRemove)
    }

    private var caption: String {
        let time = item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        if let app = item.sourceApp, !app.isEmpty { return "\(app) · \(time)" }
        return time
    }

    private var provider: NSItemProvider {
        if item.kind == .file, let path = item.text { return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
        if item.kind == .image, let img = ClipboardImageCache.image(for: item) { return NSItemProvider(object: img) }
        return NSItemProvider(object: (item.text ?? item.previewText) as NSString)
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .text:
            Text(item.previewText)
                .font(NotchFont.body)
                .foregroundStyle(NotchTheme.textPrimary)
                .lineLimit(2)
        case .link:
            HStack(spacing: 5) {
                Image(systemName: "globe").font(NotchFont.body).foregroundStyle(Color.blue)
                Text(item.previewText)
                    .font(NotchFont.body.weight(.medium))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(2)
            }
        case .color:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.small, style: .continuous)
                    .fill(Color(hex: item.text ?? "#000000"))
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: NotchTheme.Radius.small, style: .continuous)
                        .strokeBorder(NotchTheme.stroke))
                Text(item.text ?? "").font(NotchFont.label.monospaced()).foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
            }
        case .image:
            if let img = ClipboardImageCache.image(for: item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.small, style: .continuous))
            } else {
                Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(NotchTheme.textTertiary)
            }
        case .file:
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.text ?? ""))
                    .resizable().frame(width: 32, height: 32)
                Text(item.previewText)
                    .font(NotchFont.label)
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Compact

struct ClipboardCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View { ClipboardCompactBody(clipboard: vm.clipboard) }
}

private struct ClipboardCompactBody: View {
    @ObservedObject var clipboard: ClipboardService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: clipboard.items.first?.symbol ?? "list.clipboard.fill")
                .font(NotchFont.body)
                .foregroundStyle(NotchTheme.accent(for: .clipboard))
                .accessibilityHidden(true)
            Text(clipboard.items.first?.previewText.nonEmpty ?? "Área de transferência")
                .font(NotchFont.body.weight(.semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
