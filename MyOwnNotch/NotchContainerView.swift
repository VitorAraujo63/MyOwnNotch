//
//  NotchContainerView.swift
//  MyOwnNotch
//
//  View raiz hospedada na janela flutuante. Controla o tamanho
//  e a forma do Notch baseado no estado do ViewModel.
//

import SwiftUI

/// Valores que, ao mudarem, animam o tamanho/forma da ilha (uma única animação, `Motion.island`).
private struct IslandAnimationKey: Equatable {
    let state: NotchState
    let hasActivity: Bool
    let module: NotchModule
}

struct NotchContainerView: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var hasAppeared = false
    @State private var bootTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            NotchIslandView()
                .frame(width: vm.islandSize.width, height: vm.islandSize.height)
                .contentShape(NotchShape(topRadius: vm.metrics.topRadius(for: vm.state),
                                         bottomRadius: vm.metrics.bottomRadius(for: vm.state)))
                .onTapGesture {
                    if vm.state == .idle || vm.state == .compact {
                        vm.openPrimaryActivity()
                    }
                }
                .motionAnimation(Motion.island,
                                 value: IslandAnimationKey(state: vm.state,
                                                           hasActivity: vm.hasLiveActivity,
                                                           module: vm.activeModule))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // O notch físico gera safe area no topo; a ilha precisa ficar rente à borda da tela
        .ignoresSafeArea()
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if UserDefaults.standard.bool(forKey: SettingsKey.calendarEnabled) { vm.calendar.start() }
            startBoot()
        }
        // Qualquer interação do usuário cancela a animação de boot
        .onChange(of: vm.isHovered) { _, hovered in if hovered { bootTask?.cancel() } }
        .onChange(of: vm.state) { _, new in if new == .expanded { bootTask?.cancel() } }
        .onDisappear { bootTask?.cancel() }
    }

    /// Mostra a bateria brevemente ao abrir (só em Macs com bateria). Cancelável.
    private func startBoot() {
        bootTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, vm.state == .idle, !vm.isHovered,
                  vm.hasBattery, vm.isModuleVisible(.battery) else { return }
            vm.showCompact(module: .battery, duration: 2.5)
        }
    }
}

// MARK: - A Ilha Principal

struct NotchIslandView: View {
    @EnvironmentObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Conteúdo expandido: entra com fade + leve scale (ancorado no topo) depois que a forma
    /// começa a crescer; ao recolher some rápido, antes de a forma voltar para trás do notch.
    private var expandedTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .animation(Motion.content.delay(0.1)),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.1))
        )
    }

    var body: some View {
        let shape = NotchShape(topRadius: vm.metrics.topRadius(for: vm.state),
                               bottomRadius: vm.metrics.bottomRadius(for: vm.state))
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(vm.state == .expanded ? 0.55 : 0.0),
                        radius: 12, y: 4)

            Group {
                switch vm.state {
                case .idle:     IdleView()
                case .compact:  CompactView()
                case .expanded:
                    // Diagrama no tamanho final e deixa a forma animada só "revelar" o conteúdo,
                    // em vez de reorganizar o layout (e o terminal) a cada quadro do crescimento
                    ExpandedView()
                        .frame(width: vm.islandSize.width, height: vm.islandSize.height, alignment: .top)
                        .transition(expandedTransition)
                }
            }
            .clipShape(shape)
        }
        .opacity(isHiddenIdle ? 0 : 1)
    }

    /// Em Macs sem notch não desenha uma pílula preta vazia quando ocioso.
    var isHiddenIdle: Bool {
        !vm.metrics.hasNotch && vm.state == .idle && !vm.hasLiveActivity
    }
}

// MARK: - Estado Idle

struct IdleView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        // Conteúdo fica nas "asas" laterais; o centro é o notch físico (câmera)
        let inset = vm.metrics.topRadius(for: .idle)
        let wing = NotchMetrics.wingWidth - inset
        HStack(spacing: 0) {
            if let primary = vm.primaryLiveActivity {
                LiveActivityLeading(activity: primary)
                    .frame(width: wing, alignment: .trailing)
                    .padding(.leading, inset)

                Spacer(minLength: vm.metrics.hardwareWidth)

                LiveActivityTrailing(activity: primary, secondary: vm.secondaryLiveActivity)
                    .frame(width: wing, alignment: .leading)
                    .padding(.trailing, inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vm.idleAccessibilityLabel)
        .accessibilityAddTraits(vm.hasLiveActivity ? .isButton : [])
    }
}

// MARK: - Estado Compact

struct CompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        // Conteúdo na faixa abaixo do notch físico, para nunca ficar atrás da câmera
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.metrics.hardwareHeight)
            HStack(spacing: 8) {
                switch vm.activeModule {
                case .media:         MediaCompactView()
                case .battery:       BatteryCompactView()
                case .timer:         TimerCompactView()
                case .systemMonitor: SystemCompactView()
                case .weather:       WeatherCompactView()
                case .volume:        VolumeCompactView()
                case .terminal:      TerminalCompactView()
                case .crypto:        CryptoCompactView()
                case .tray:          TrayCompactView()
                case .agent:         AgentCompactView()
                case .github:        GitHubCompactView()
                case .calendar:      CalendarCompactView()
                default:             EmptyView()
                }
            }
            .padding(.horizontal, vm.metrics.topRadius(for: .compact) + 12)
            .frame(maxWidth: .infinity)
            .frame(height: NotchMetrics.compactStripHeight - 4)
            .padding(.bottom, 4)
        }
        .transition(.opacity)
    }
}

// MARK: - Estado Expanded

struct ExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNS

    /// Direção da última troca de aba (+1 = para a direita), usada no deslocamento do conteúdo.
    @State private var direction: CGFloat = 1
    @State private var swipeMonitor: Any?
    @State private var swipeAccum: CGFloat = 0
    @State private var swipeHandled = false

    private struct Tab {
        let module: NotchModule
        let icon: String
        let title: String
    }

    /// Ordem fixa das abas; só as visíveis (Ajustes) aparecem.
    private static let allTabs: [Tab] = [
        Tab(module: .media, icon: "music.note", title: "Mídia"),
        Tab(module: .battery, icon: "bolt.fill", title: "Bateria"),
        Tab(module: .weather, icon: "cloud.sun.fill", title: "Clima"),
        Tab(module: .systemMonitor, icon: "cpu", title: "Sistema"),
        Tab(module: .agent, icon: "sparkle", title: "Claude"),
        Tab(module: .github, icon: "arrow.triangle.branch", title: "GitHub"),
        Tab(module: .tray, icon: "tray.full.fill", title: "Bandeja"),
        Tab(module: .crypto, icon: "chart.xyaxis.line", title: "Cotações"),
        Tab(module: .terminal, icon: "terminal.fill", title: "Terminal"),
        Tab(module: .timer, icon: "timer", title: "Timer"),
        Tab(module: .calendar, icon: "calendar", title: "Calendário"),
    ]

    private var tabs: [Tab] { Self.allTabs.filter { vm.isModuleVisible($0.module) } }

    /// Módulos com campo de texto/terminal: teclas soltas (setas, Esc) pertencem a eles.
    private var ownsKeyboard: Bool {
        [.terminal, .agent, .weather, .github].contains(vm.activeModule)
    }

    var body: some View {
        let sidePadding = vm.metrics.topRadius(for: .expanded) + 14
        let all = tabs
        let split = (all.count + 1) / 2

        VStack(spacing: 0) {
            // ── Linha do notch: abas nas laterais, câmera no centro ──
            HStack(spacing: 0) {
                HStack(spacing: NotchTheme.Spacing.xs) {
                    ForEach(all.prefix(split), id: \.module) { tabButton($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: vm.metrics.hardwareWidth)

                HStack(spacing: NotchTheme.Spacing.xs) {
                    ForEach(all.dropFirst(split), id: \.module) { tabButton($0) }
                    closeButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, sidePadding)
            .frame(height: vm.metrics.hardwareHeight)

            // ── Conteúdo ──
            Group {
                switch vm.activeModule {
                case .media:         MediaExpandedView()
                case .battery:       BatteryExpandedView()
                case .weather:       WeatherExpandedView()
                case .systemMonitor: SystemExpandedView()
                case .crypto:        CryptoExpandedView()
                case .terminal:      TerminalExpandedView()
                case .timer:         TimerExpandedView()
                case .tray:          TrayExpandedView()
                case .agent:         AgentExpandedView()
                case .github:        GitHubExpandedView()
                case .calendar:      CalendarExpandedView()
                default:             MediaExpandedView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, sidePadding + 4)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Conteúdo antigo some rápido e o novo só aparece com a ilha já crescendo,
            // senão ele surge no tamanho final dentro de uma ilha ainda pequena (efeito de "reabrir")
            .transition(.asymmetric(
                insertion: .opacity
                    .combined(with: .offset(x: reduceMotion ? 0 : 8 * direction))
                    .animation(.easeOut(duration: 0.2).delay(0.08)),
                removal: .opacity.animation(.easeIn(duration: 0.08))))
            .id(vm.activeModule)
        }
        .background(shortcutButtons(all))
        .onAppear(perform: installSwipeMonitor)
        .onDisappear(perform: removeSwipeMonitor)
    }

    // MARK: Abas

    private func tabButton(_ tab: Tab) -> some View {
        let selected = vm.activeModule == tab.module
        return Button { select(tab.module) } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? NotchTheme.textPrimary : NotchTheme.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    Group {
                        if selected {
                            Capsule()
                                .fill(NotchTheme.fillSelected)
                                .matchedGeometryEffect(id: "tab_bg", in: tabNS)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var closeButton: some View {
        Button { vm.collapse() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NotchTheme.textTertiary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(NotchTheme.fillSubtle))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fechar")
        .accessibilityLabel("Fechar")
    }

    private func select(_ module: NotchModule) {
        guard module != vm.activeModule else { return }
        let order = tabs.map(\.module)
        if let from = order.firstIndex(of: vm.activeModule), let to = order.firstIndex(of: module) {
            direction = to >= from ? 1 : -1
        }
        withAnimation(Motion.animation(Motion.island, reduceMotion: reduceMotion)) {
            vm.activeModule = module
        }
    }

    /// Move para a aba vizinha (+1 / -1), sem dar a volta.
    private func step(_ delta: Int) {
        let order = tabs.map(\.module)
        guard let current = order.firstIndex(of: vm.activeModule) else { return }
        let target = current + delta
        guard order.indices.contains(target) else { return }
        select(order[target])
    }

    // MARK: Atalhos

    /// Botões invisíveis que carregam os atalhos de teclado (⌘1–⌘9, setas, Esc).
    private func shortcutButtons(_ all: [Tab]) -> some View {
        ZStack {
            ForEach(Array(all.prefix(9).enumerated()), id: \.offset) { index, tab in
                if let key = "\(index + 1)".first {
                    Button("") { select(tab.module) }
                        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                }
            }
            // ⌘←/→ em campos de texto/terminal significam "início/fim da linha"
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: .command).disabled(ownsKeyboard)
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: .command).disabled(ownsKeyboard)
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(ownsKeyboard)
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(ownsKeyboard)
            Button("") { vm.collapse() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(vm.activeModule == .terminal || vm.activeModule == .agent)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Swipe horizontal (trackpad)

    /// Observa (sem consumir) o scroll horizontal do trackpad; só gestos predominantemente
    /// horizontais trocam de aba, então a rolagem vertical interna não é afetada.
    private func installSwipeMonitor() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.window is NotchWindow, !event.phase.isEmpty,
                  vm.activeModule != .terminal, vm.activeModule != .agent else { return event }
            if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
                swipeAccum = 0
                swipeHandled = false
            }
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 {
                swipeAccum += event.scrollingDeltaX
                if !swipeHandled, abs(swipeAccum) > 60 {
                    swipeHandled = true
                    step(swipeAccum < 0 ? 1 : -1)
                }
            }
            return event
        }
    }

    private func removeSwipeMonitor() {
        if let m = swipeMonitor { NSEvent.removeMonitor(m) }
        swipeMonitor = nil
    }
}
