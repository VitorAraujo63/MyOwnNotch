//
//  NotchContainerView.swift
//  MyOwnNotch
//
//  View raiz hospedada na janela flutuante. Controla o tamanho
//  e a forma do Notch baseado no estado do ViewModel.
//

import SwiftUI

struct NotchContainerView: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var hasAppeared = false

    private let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.88)

    var body: some View {
        ZStack(alignment: .top) {
            NotchIslandView()
                .frame(width: vm.islandSize.width, height: vm.islandSize.height)
                .contentShape(NotchShape(topRadius: vm.metrics.topRadius(for: vm.state),
                                         bottomRadius: vm.metrics.bottomRadius(for: vm.state)))
                .onTapGesture {
                    if vm.state == .idle || vm.state == .compact {
                        let moduleToOpen: NotchModule = !vm.mediaSource.isEmpty ? .media : .battery
                        vm.expand(module: moduleToOpen)
                    }
                }
                .animation(islandSpring, value: vm.state)
                .animation(islandSpring, value: vm.mediaIsPlaying)
                .animation(islandSpring, value: vm.activeModule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // O notch físico gera safe area no topo; a ilha precisa ficar rente à borda da tela
        .ignoresSafeArea()
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(islandSpring) {
                    vm.state = .compact
                    vm.activeModule = .battery
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if vm.state == .compact { vm.collapse() }
            }
        }
    }
}

// MARK: - A Ilha Principal

struct NotchIslandView: View {
    @EnvironmentObject var vm: NotchViewModel

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
                }
            }
            .clipShape(shape)
        }
        .opacity(isHiddenIdle ? 0 : 1)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: vm.state)
    }

    /// Em Macs sem notch não desenha uma pílula preta vazia quando ocioso.
    var isHiddenIdle: Bool {
        !vm.metrics.hasNotch && vm.state == .idle && !vm.mediaIsPlaying
    }
}

// MARK: - Estado Idle

struct IdleView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        // Conteúdo fica nas "asas" laterais; o centro é o notch físico (câmera)
        HStack(spacing: 0) {
            if vm.mediaIsPlaying {
                Group {
                    if let art = vm.mediaArtwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: NotchMetrics.wingWidth, alignment: .trailing)
                .padding(.leading, vm.metrics.topRadius(for: .idle))

                Spacer(minLength: vm.metrics.hardwareWidth)

                AudioBarsView(bars: vm.audioBars, color: .white.opacity(0.6), barWidth: 2, maxHeight: 12)
                    .frame(width: NotchMetrics.wingWidth, alignment: .leading)
                    .padding(.trailing, vm.metrics.topRadius(for: .idle))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
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
    @Namespace private var tabNS

    let leftTabs: [(NotchModule, String)] = [
        (.media, "music.note"),
        (.battery, "bolt.fill"),
        (.weather, "cloud.sun.fill"),
        (.systemMonitor, "cpu"),
        (.agent, "sparkle"),
    ]
    let rightTabs: [(NotchModule, String)] = [
        (.github, "arrow.triangle.branch"),
        (.tray, "tray.full.fill"),
        (.crypto, "chart.xyaxis.line"),
        (.terminal, "terminal.fill"),
        (.timer, "timer"),
    ]

    var body: some View {
        let sidePadding = vm.metrics.topRadius(for: .expanded) + 14

        VStack(spacing: 0) {
            // ── Linha do notch: abas nas laterais, câmera no centro ──
            HStack(spacing: 0) {
                HStack(spacing: 1) { ForEach(leftTabs, id: \.0) { tabButton($0.0, $0.1) } }
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: vm.metrics.hardwareWidth)

                HStack(spacing: 1) {
                    ForEach(rightTabs, id: \.0) { tabButton($0.0, $0.1) }
                    Button { vm.collapse() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                removal: .opacity.animation(.easeIn(duration: 0.08))))
            .id(vm.activeModule)
        }
    }

    private func tabButton(_ module: NotchModule, _ icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                vm.activeModule = module
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(vm.activeModule == module ? .white : .white.opacity(0.35))
                .frame(width: 25, height: 26)
                .background(
                    Group {
                        if vm.activeModule == module {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .matchedGeometryEffect(id: "tab_bg", in: tabNS)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
