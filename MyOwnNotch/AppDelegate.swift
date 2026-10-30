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
        UserDefaults.standard.register(defaults: [SettingsKey.showMenuBarIcon: true])
        setupMenuBar()
        observeMenuBarIconVisibility()
        setupNotchWindow()
    }

    /// Com o ícone oculto, abrir o app de novo (Finder/Spotlight/Launchpad) leva aos Ajustes,
    /// de onde o ícone pode ser reexibido.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
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
        menu.addItem(NSMenuItem(title: "🐙 GitHub", action: #selector(showGitHub), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: "📈 Monitor do sistema", action: #selector(showSystemMonitor), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "📅 Calendário", action: #selector(showCalendar), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "📋 Clipboard", action: #selector(showClipboard), keyEquivalent: "v"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Recolher Notch", action: #selector(collapseNotch), keyEquivalent: "escape"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sair do MyOwnNotch", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
        updateMenuBarIconVisibility()
    }

    private func observeMenuBarIconVisibility() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarIconVisibility() }
            .store(in: &cancellables)
    }

    private func updateMenuBarIconVisibility() {
        let visible = UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarIcon)
        if statusItem?.isVisible != visible { statusItem?.isVisible = visible }
    }

    @objc private func showMedia() { notchViewModel.expand(module: .media) }
    @objc private func showTimer() { notchViewModel.expand(module: .timer) }
    @objc private func showBattery() { notchViewModel.expand(module: .battery) }
    @objc private func showWeather() { notchViewModel.expand(module: .weather) }
    @objc private func showTerminal() { notchViewModel.expand(module: .terminal) }
    @objc private func showTray() { notchViewModel.expand(module: .tray) }
    @objc private func showAgent() { notchViewModel.expand(module: .agent) }
    @objc private func showCrypto() { notchViewModel.expand(module: .crypto) }
    @objc private func showGitHub() { notchViewModel.expand(module: .github) }
    @objc private func showSystemMonitor() { notchViewModel.expand(module: .systemMonitor) }
    @objc private func showCalendar() { notchViewModel.expand(module: .calendar) }
    @objc private func showClipboard() { notchViewModel.expand(module: .clipboard) }

    // MARK: - Ajustes

    private var settingsWindow: NSWindow?

    @objc func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Ajustes"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func collapseNotch() { notchViewModel.collapse() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Notch Window

    private var cancellables = Set<AnyCancellable>()

    /// Tela onde o notch vive (prefere a com notch físico).
    /// Estável: só é recalculada em mudanças de tela, wake e troca de Space.
    private lazy var targetScreen: NSScreen? = NotchMetrics.preferredScreen()

    /// Frame da janela para o estado atual: ilha + margem transparente (sombra), centrada
    /// no topo da tela. A janela acompanha o tamanho da ilha para não bloquear cliques
    /// na menu bar ao redor.
    private func windowFrame(state: NotchState? = nil, hasActivity: Bool? = nil) -> NSRect? {
        guard let screen = targetScreen else { return nil }
        let vm = notchViewModel
        let st = state ?? vm.state
        // Expandido: a janela já nasce no maior tamanho (terminal) e não muda ao trocar de aba,
        // assim o redimensionamento da janela nunca interfere na animação da ilha.
        let island = vm.metrics.islandSize(for: st, hasActivity: hasActivity ?? vm.hasLiveActivity,
                                           module: st == .expanded ? .terminal : vm.activeModule)
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
        defer { updateHostingFrame() }   // recentraliza DEPOIS de a janela mudar de tamanho
        guard let frame = windowFrame(), let window = notchWindow, window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: false)
    }

    /// Hosting view do SwiftUI: tamanho FIXO (maior frame possível da janela), centrado no
    /// container e ancorado no topo. Assim o sistema de coordenadas do SwiftUI não muda quando a
    /// janela cresce/encolhe e a ilha nasce sempre do mesmo ponto (o notch).
    private var hostingView: NSView?
    private var hostingContainer: NSView?

    private func maxWindowSize() -> NSSize? {
        let states: [(NotchState, Bool)] = [(.expanded, false), (.expanded, true), (.compact, true), (.idle, true)]
        let frames = states.compactMap { windowFrame(state: $0.0, hasActivity: $0.1) }
        guard !frames.isEmpty else { return nil }
        return NSSize(width: frames.map(\.width).max() ?? 0, height: frames.map(\.height).max() ?? 0)
    }

    private func updateHostingFrame() {
        guard let container = hostingContainer, let host = hostingView, let size = maxWindowSize() else { return }
        let bounds = container.bounds
        let target = NSRect(x: ((bounds.width - size.width) / 2).rounded(),
                            y: bounds.height - size.height,
                            width: size.width, height: size.height)
        if host.frame != target { host.frame = target }
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
        self.hostingView = hostingView
        hostingView.sizingOptions = []   // a janela dita o tamanho, não o conteúdo
        // O hosting view fica dentro de um container simples (autoresizing, sem constraints),
        // senão o SwiftUI tenta mexer no tamanho da janela durante o layout e o AppKit aborta.
        let container = CenteringContainerView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        hostingContainer = container
        // Sem autoresizing: com o hosting view maior que a janela, o AppKit redistribui as margens
        // de forma imprevisível ao encolher (a ilha ficava deslocada e cortada). O container
        // recentraliza explicitamente a cada mudança de tamanho.
        hostingView.autoresizingMask = []
        container.onResize = { [weak self] in self?.updateHostingFrame() }
        container.addSubview(hostingView)
        updateHostingFrame()

        // Camada de drop POR CIMA do SwiftUI (o hosting view disputava o alvo do arrasto)
        let dropView = FileDropView(frame: container.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onTargeted = { [weak self] targeted in self?.notchViewModel.isDropTargeted = targeted }
        dropView.onDrop = { [weak self] urls in
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            self?.notchViewModel.addToTray(urls)
        }
        container.addSubview(dropView)
        notchWindow?.contentView = container
        notchWindow?.setFrame(frame, display: true)
        notchWindow?.orderFrontRegardless()

        // Inicialmente ignora cliques para não bloquear a tela quando idle
        notchWindow?.ignoresMouseEvents = true

        // Cresce a janela ANTES da animação (síncrono, no willSet); encolhe só depois que ela termina
        notchViewModel.$state
            .combineLatest(notchViewModel.$liveActivities.map { !$0.isEmpty })
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] newState, hasActivity in
                guard let self, let window = self.notchWindow,
                      let target = self.windowFrame(state: newState, hasActivity: hasActivity) else { return }
                if target.width >= window.frame.width && target.height >= window.frame.height {
                    if window.frame != target {
                        window.setFrame(target, display: true, animate: false)
                        self.updateHostingFrame()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        self?.applyWindowFrame()
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(screensChanged),
                       name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensChanged),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        setupMouseTracking()
    }

    @objc private func screensChanged() {
        targetScreen = NotchMetrics.preferredScreen()
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
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
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

    // MARK: - Swipe para pular faixa

    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var swipeAccumX: CGFloat = 0
    private var swipeAccumY: CGFloat = 0
    private var swipeHandled = false
    /// Com música e swipe ligado, o hover espera um instante antes de expandir,
    /// para dar tempo do swipe de dois dedos (que cancela a expansão).
    private var pendingHoverExpand: DispatchWorkItem?
    private static let hoverExpandDelay: TimeInterval = 0.3

    /// Cache da preferência (o monitor global recebe todo scroll do sistema; não ler UserDefaults por evento).
    private var swipeSettingEnabled = true
    private func refreshSwipeSetting() {
        swipeSettingEnabled = UserDefaults.standard.object(forKey: SettingsKey.swipeToSkipTrack) as? Bool ?? true
    }

    private var swipeToSkipEnabled: Bool {
        swipeSettingEnabled && !notchViewModel.mediaSource.isEmpty
    }

    private func expandFromHover() {
        pendingHoverExpand?.cancel(); pendingHoverExpand = nil
        let vm = notchViewModel
        guard vm.isHovered, vm.state == .idle || vm.state == .compact else { return }
        vm.openPrimaryActivity()
        if vm.state == .expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }
    private static let swipeThreshold: CGFloat = 60

    private func setupScrollTracking() {
        refreshSwipeSetting()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSwipeSetting() }
            .store(in: &cancellables)
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleSwipe(event)
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleSwipe(event)
            return event
        }
    }

    /// Dois dedos sobre o notch recolhido: esquerda = próxima faixa, direita = anterior.
    /// Uma ação por gesto (reinicia no início da fase).
    private func handleSwipe(_ event: NSEvent) {
        // Saídas baratas primeiro: este handler roda para todo scroll do sistema
        let vm = notchViewModel
        guard vm.state == .idle || vm.state == .compact,
              event.hasPreciseScrollingDeltas,
              swipeSettingEnabled,
              !vm.mediaSource.isEmpty else { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipeAccumX = 0; swipeAccumY = 0; swipeHandled = false
        }
        // Inércia não conta como novo gesto
        guard event.momentumPhase.isEmpty, !swipeHandled else { return }

        guard let screen = targetScreen,
              notchHitRect(on: screen).contains(NSEvent.mouseLocation) else { return }

        // Gesto em andamento sobre o notch: segura a expansão por hover até ele terminar
        pendingHoverExpand?.cancel(); pendingHoverExpand = nil
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if !swipeHandled { expandFromHover() }
            return
        }

        swipeAccumX += event.scrollingDeltaX
        swipeAccumY += event.scrollingDeltaY
        guard abs(swipeAccumX) > Self.swipeThreshold, abs(swipeAccumX) > abs(swipeAccumY) * 1.5 else { return }

        swipeHandled = true
        if swipeAccumX < 0 { vm.mediaNext() } else { vm.mediaPrevious() }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        vm.showCompact(module: .media, duration: 2)
    }

    private func setupMouseTracking() {
        setupScrollTracking()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.checkMousePosition(event.type)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.checkMousePosition(event.type)
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        if let m = globalScrollMonitor { NSEvent.removeMonitor(m) }
        if let m = localScrollMonitor { NSEvent.removeMonitor(m) }
        globalScrollMonitor = nil
        localScrollMonitor = nil
        NotificationCenter.default.removeObserver(self)
        notchViewModel.terminal.terminate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Mesma geometria da ilha desenhada, centrada no topo da tela.
    /// Estende 2pt acima da borda: com o mouse colado no topo, y == maxY e
    /// NSRect.contains (intervalo aberto) falharia.
    private func notchHitRect(on screen: NSScreen) -> NSRect {
        let island = notchViewModel.islandSize
        let slop: CGFloat = notchViewModel.state == .idle ? 4 : 0
        return NSRect(
            x: screen.frame.midX - island.width / 2 - slop,
            y: screen.frame.maxY - island.height,
            width: island.width + 2 * slop,
            height: island.height + 2 + slop
        )
    }

    private func checkMousePosition(_ eventType: NSEvent.EventType = .mouseMoved) {
        guard let screen = targetScreen, let window = notchWindow else { return }
        let mouseLoc = NSEvent.mouseLocation
        let notchRect = notchHitRect(on: screen)

        let isHovering = notchRect.contains(mouseLoc)

        // Arrasto de arquivo em andamento: abre a bandeja ANTES de o mouse chegar ao topo,
        // para o drop cair dentro dela (e não na janela de trás ou na borda, que aciona o Mission Control).
        let wasDragging = isFileDragging
        if eventType == .leftMouseDragged || eventType == .leftMouseUp || wasDragging {
            updateFileDragState()
        }
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
                    if swipeToSkipEnabled && !isFileDragging {
                        let work = DispatchWorkItem { [weak self] in self?.expandFromHover() }
                        pendingHoverExpand?.cancel()
                        pendingHoverExpand = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverExpandDelay, execute: work)
                    } else {
                        expandFromHover()
                    }
                }
            } else {
                pendingHoverExpand?.cancel(); pendingHoverExpand = nil
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


/// Container da janela do notch: avisa quando muda de tamanho para o hosting view (de tamanho
/// fixo) ser recentralizado e ancorado no topo.
final class CenteringContainerView: NSView {
    var onResize: (() -> Void)?
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        onResize?()
    }
}
