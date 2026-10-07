//
//  AppDelegate.swift
//  MyOwnNotch
//
//  Gerencia o ciclo de vida do app, cria a janela flutuante do notch
//  e o ícone da barra de menus.
//

import AppKit
import SwiftUI
import UserNotifications
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    var notchWindow: NotchWindow?
    var statusItem: NSStatusItem?
    let notchViewModel = NotchViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        setupMenuBar()
        setupNotchWindow()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MyOwnNotch")?
                .withSymbolConfiguration(config)
            button.image?.isTemplate = true
            button.toolTip = "MyOwnNotch"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "▶ Player de Música", action: #selector(showMedia), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "⏱ Timer", action: #selector(showTimer), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "🔋 Bateria", action: #selector(showBattery), keyEquivalent: "b"))
        menu.addItem(NSMenuItem(title: "🌤 Clima", action: #selector(showWeather), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "💻 Terminal", action: #selector(showTerminal), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "🗂 Bandeja de Arquivos", action: #selector(showTray), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: "✨ Claude", action: #selector(showAgent), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "📊 Crypto", action: #selector(showCrypto), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Recolher Notch", action: #selector(collapseNotch), keyEquivalent: "escape"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sair do MyOwnNotch", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showMedia() { notchViewModel.expand(module: .media) }
    @objc private func showTimer() { notchViewModel.expand(module: .timer) }
    @objc private func showBattery() { notchViewModel.expand(module: .battery) }
    @objc private func showWeather() { notchViewModel.expand(module: .weather) }
    @objc private func showTerminal() { notchViewModel.expand(module: .terminal) }
    @objc private func showTray() { notchViewModel.expand(module: .tray) }
    @objc private func showAgent() { notchViewModel.expand(module: .agent) }
    @objc private func showCrypto() { notchViewModel.expand(module: .crypto) }
    @objc private func collapseNotch() { notchViewModel.collapse() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Notch Window

    private var cancellables = Set<AnyCancellable>()

    /// Tela onde o notch vive (prefere a com notch físico).
    private var targetScreen: NSScreen? { NotchMetrics.preferredScreen() }

    /// Frame da janela para o estado atual: ilha + margem transparente (sombra), centrada
    /// no topo da tela. A janela acompanha o tamanho da ilha para não bloquear cliques
    /// na menu bar ao redor.
    private func windowFrame() -> NSRect? {
        guard let screen = targetScreen else { return nil }
        let island = notchViewModel.islandSize
        let pad = NotchMetrics.windowPadding
        let width = island.width + 2 * pad
        let height = island.height + pad
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func applyWindowFrame(animated: Bool = false) {
        guard let frame = windowFrame(), let window = notchWindow, window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: false)
    }

    private func setupNotchWindow() {
        notchViewModel.metrics = NotchMetrics.measure(targetScreen)
        guard let frame = windowFrame() else { return }

        notchWindow = NotchWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let rootView = NotchContainerView().environmentObject(notchViewModel)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []   // a janela dita o tamanho, não o conteúdo
        // O hosting view fica dentro de um container simples (autoresizing, sem constraints),
        // senão o SwiftUI tenta mexer no tamanho da janela durante o layout e o AppKit aborta.
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        // Camada de drop POR CIMA do SwiftUI (o hosting view disputava o alvo do arrasto)
        let dropView = FileDropView(frame: container.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onTargeted = { [weak self] targeted in self?.notchViewModel.isDropTargeted = targeted }
        dropView.onDrop = { [weak self] urls in self?.notchViewModel.addToTray(urls) }
        container.addSubview(dropView)
        notchWindow?.contentView = container
        notchWindow?.setFrame(frame, display: true)
        notchWindow?.orderFrontRegardless()

        // Inicialmente ignora cliques para não bloquear a tela quando idle
        notchWindow?.ignoresMouseEvents = true

        // Cresce a janela antes da animação; encolhe só depois que ela termina
        notchViewModel.$state
            .combineLatest(notchViewModel.$mediaIsPlaying, notchViewModel.$activeModule)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard let target = self.windowFrame(), let window = self.notchWindow else { return }
                    if target.width >= window.frame.width && target.height >= window.frame.height {
                        self.applyWindowFrame()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                            self?.applyWindowFrame()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        setupMouseTracking()
    }

    @objc private func screensChanged() {
        notchViewModel.metrics = NotchMetrics.measure(targetScreen)
        applyWindowFrame()
    }

    // MARK: - Mouse Tracking

    /// Recolhe 1s depois que o mouse sai. Não recolhe durante um arrasto (botão pressionado),
    /// para não destruir a bandeja no meio de um drag-and-drop, nem enquanto o terminal está aberto.
    private func scheduleCollapse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.notchViewModel.isHovered, self.notchViewModel.state == .expanded else { return }
            if NSEvent.pressedMouseButtons != 0 { self.scheduleCollapse(); return }
            // No terminal o notch fica aberto enquanto você digita; feche pelo ✕
            if self.notchViewModel.activeModule != .terminal && self.notchViewModel.activeModule != .agent { self.notchViewModel.collapse() }
        }
    }
    private var mouseCheckTimer: Timer?
    private var lastDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var isFileDragging = false

    /// Detecta um arrasto de arquivos em andamento (botão pressionado + pasteboard de drag mudou)
    private func updateFileDragState() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let pb = NSPasteboard(name: .drag)
        if pressed {
            if pb.changeCount != lastDragChangeCount {
                isFileDragging = pb.canReadObject(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true])
            }
        } else {
            isFileDragging = false
        }
        lastDragChangeCount = pb.changeCount
    }

    private func setupMouseTracking() {
        mouseCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        guard let screen = targetScreen, let window = notchWindow else { return }
        let mouseLoc = NSEvent.mouseLocation

        // Mesma geometria da ilha desenhada, centrada no topo da tela.
        // Estende 2pt acima da borda: com o mouse colado no topo, y == maxY e
        // NSRect.contains (intervalo aberto) falharia.
        let island = notchViewModel.islandSize
        let slop: CGFloat = notchViewModel.state == .idle ? 4 : 0
        let notchRect = NSRect(
            x: screen.frame.midX - island.width / 2 - slop,
            y: screen.frame.maxY - island.height,
            width: island.width + 2 * slop,
            height: island.height + 2 + slop
        )

        let isHovering = notchRect.contains(mouseLoc)

        // Arrasto de arquivo em andamento: abre a bandeja ANTES de o mouse chegar ao topo,
        // para o drop cair dentro dela (e não na janela de trás ou na borda, que aciona o Mission Control).
        let wasDragging = isFileDragging
        updateFileDragState()
        FileDropView.dragActive = isFileDragging
        if isFileDragging {
            if notchViewModel.state != .expanded || notchViewModel.activeModule != .tray {
                notchViewModel.expand(module: .tray)
            }
            if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
            window.orderFrontRegardless()
        } else if wasDragging && !notchViewModel.isHovered {
            scheduleCollapse()   // arrasto terminou fora da bandeja
        }

        if isHovering != notchViewModel.isHovered {
            notchViewModel.isHovered = isHovering
            if isHovering {
                if notchViewModel.state == .idle || notchViewModel.state == .compact {
                    let m: NotchModule = !notchViewModel.mediaSource.isEmpty ? .media : .battery
                    notchViewModel.expand(module: m)
                }
            } else {
                if notchViewModel.state == .expanded {
                    scheduleCollapse()
                }
            }
        }

        // Libera a tela para cliques quando o notch estiver idle!
        let shouldIgnore = (notchViewModel.state == .idle)
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
    }
}
