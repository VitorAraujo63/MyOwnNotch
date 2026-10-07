//
//  NotchWindow.swift
//  MyOwnNotch
//
//  Subclasse de NSPanel configurada para flutuar sobre tudo,
//  ser transparente e ignorar cliques onde não há conteúdo.
//

import AppKit

class NotchWindow: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        // Adiciona .nonactivatingPanel para não roubar o foco do app ativo
        var style = style
        style.insert(.nonactivatingPanel)

        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: bufferingType,
            defer: flag
        )

        // Configurações de aparência
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        // Acima da menu bar, mas abaixo do nível screenSaver: janelas de nível muito alto
        // não são consideradas como destino de drag-and-drop pelo sistema.
        self.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        self.collectionBehavior = [
            .canJoinAllSpaces,         // Aparece em todos os Spaces
            .stationary,               // Não se move com outros apps
            .fullScreenAuxiliary,      // Aparece também sobre apps em tela cheia
            .ignoresCycle              // Não aparece no Cmd+Tab
        ]

        // Permite cliques em janelas por baixo quando não há conteúdo ativo
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
    }

    // Permite que o painel receba eventos de teclado se necessário
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Sem isso o AppKit empurra a janela para baixo da menu bar / área do notch
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}


// MARK: - Destino de arrasto (drop) em AppKit

/// View que cobre a janela inteira e recebe arquivos soltos. Feito em AppKit (e não com
/// `.onDrop` do SwiftUI) para o drop funcionar de forma confiável nesta janela flutuante.
final class FileDropView: NSView {
    /// Só intercepta o mouse durante um arrasto de arquivo; fora disso é transparente aos cliques.
    static var dragActive = false
    override func hitTest(_ point: NSPoint) -> NSView? {
        Self.dragActive ? super.hitTest(point) : nil
    }
    var onTargeted: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargeted?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted?(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onTargeted?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        onTargeted?(false)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
