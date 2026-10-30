//
//  Theme.swift
//  MyOwnNotch
//
//  Tokens de design: movimento, cores, raios, espaçamentos, fontes,
//  além de StateView (estados de carregamento) e Shimmer (skeleton).
//

import SwiftUI

// MARK: - Movimento

enum Motion {
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let content = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let micro = Animation.easeOut(duration: 0.15)

    /// Com Reduce Motion, troca a animação por um fade curto (ou nil).
    static func animation(_ a: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : a
    }
}

private struct MotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.animation(_:value:)` que respeita Reduce Motion.
    func motionAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Tokens

enum NotchTheme {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.75)
    /// Mínimo aceitável para texto.
    static let textTertiary = Color.white.opacity(0.6)
    static let fillSubtle = Color.white.opacity(0.08)
    static let fillSelected = Color.white.opacity(0.14)
    static let stroke = Color.white.opacity(0.1)

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
    }

    static func accent(for module: NotchModule) -> Color {
        switch module {
        case .media:         return .pink
        case .battery:       return .green
        case .weather:       return .cyan
        case .systemMonitor: return .orange
        case .agent:         return .purple
        case .github:        return Color(white: 0.85)
        case .tray:          return .blue
        case .crypto:        return .yellow
        case .terminal:      return .mint
        case .timer:         return .red
        case .calendar:      return .teal
        case .clipboard:     return .indigo
        case .none, .actions, .volume: return .white
        }
    }
}

extension NotchTheme {
    /// Cor de destaque efetiva para um módulo, respeitando a escolha do usuário.
    static func accent(_ module: NotchModule, choice: AccentChoice) -> Color {
        choice.color(for: module)
    }

    /// Tokens da superfície de vidro (estilo Droppy).
    enum Surface {
        /// Opacidade do preto no fundo da ilha expandida (Dynamic Glass).
        static let dynamicBottomDarkness: Double = 0.42
        /// Idem, para a faixa compacta (menor, precisa de mais contraste).
        static let compactBottomDarkness: Double = 0.62
        /// Escurecimento uniforme do Liquid Glass.
        static let liquidDarkness: Double = 0.26
        /// Intensidade da tinta da cor de destaque.
        static let tintOpacity: Double = 0.12
        static let strokeOpacity: Double = 0.14
        static let strokeWidth: CGFloat = 1
        /// Sombra externa suave quando expandido.
        static let shadowOpacity: Double = 0.38
        static let shadowRadius: CGFloat = 16
        static let shadowY: CGFloat = 6
    }
}

extension AccentChoice {
    func color(for module: NotchModule) -> Color {
        switch self {
        case .module: return NotchTheme.accent(for: module)
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        case .orange: return .orange
        case .green:  return .green
        case .mint:   return .mint
        case .white:  return .white
        }
    }
}

// MARK: - Superfície da ilha

/// Material escuro atrás da janela (borra o desktop). Criado uma vez; sem atualizações por frame.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Fundo da ilha: preto sólido ou vidro, conforme estilo e estado.
/// Idle sempre preto (funde com o notch físico); a faixa `hardwareHeight` do topo fica preta
/// fora do estado expandido. Reduce Transparency -> preto.
struct NotchSurface<S: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let style: SurfaceStyle
    let state: NotchState
    let hardwareHeight: CGFloat
    let tint: Color

    private var isGlass: Bool {
        !reduceTransparency && style != .black && state != .idle
    }

    var body: some View {
        // O blur fica sempre montado (opacidade 0 fora do vidro) para não recriar a
        // NSVisualEffectView a cada expand/collapse.
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let hw = min(hardwareHeight, h)
            ZStack {
                BehindWindowBlur()
                    .clipShape(shape)
                    .opacity(isGlass ? 1 : 0)
                ZStack {
                    tint.opacity(NotchTheme.Surface.tintOpacity)
                    LinearGradient(stops: darkStops(h: h, hw: hw), startPoint: .top, endPoint: .bottom)
                }
                .drawingGroup()
                .clipShape(shape)
                .opacity(isGlass ? 1 : 0)
                shape.fill(Color.black)
                    .opacity(isGlass ? 0 : 1)
                // Não é InsettableShape: o traço é centrado na borda e cortado pela forma,
                // então a largura 2x resulta em 1pt visível por dentro.
                shape.stroke(LinearGradient(stops: strokeStops(h: h, hw: hw),
                                            startPoint: .top, endPoint: .bottom),
                             lineWidth: NotchTheme.Surface.strokeWidth * 2)
                    .clipShape(shape)
                    .opacity(isGlass ? 1 : 0)
            }
        }
        .background(shadowLayer)
    }

    private func darkStops(h: CGFloat, hw: CGFloat) -> [Gradient.Stop] {
        let f = Double(hw / h)
        switch style {
        case .liquidGlass:
            let d = NotchTheme.Surface.liquidDarkness
            if state == .expanded {
                // Preto curto no topo, depois vidro claro
                let end = min(1, f * 0.8)
                return [.init(color: .black, location: 0),
                        .init(color: .black, location: end * 0.5),
                        .init(color: .black.opacity(d), location: end),
                        .init(color: .black.opacity(d), location: 1)]
            }
            return [.init(color: .black, location: 0),
                    .init(color: .black, location: f),
                    .init(color: .black.opacity(d + 0.2), location: min(1, f + 0.02)),
                    .init(color: .black.opacity(d + 0.2), location: 1)]
        default:
            let bottom = state == .expanded ? NotchTheme.Surface.dynamicBottomDarkness
                                            : NotchTheme.Surface.compactBottomDarkness
            return [.init(color: .black, location: 0),
                    .init(color: .black, location: f),
                    .init(color: .black.opacity(bottom), location: 1)]
        }
    }

    private func strokeStops(h: CGFloat, hw: CGFloat) -> [Gradient.Stop] {
        let f = Double(hw / h)
        let o = NotchTheme.Surface.strokeOpacity
        // Sem borda na faixa preta do notch; a borda de vidro nasce abaixo dela
        return [.init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: f * 0.9),
                .init(color: .white.opacity(o + 0.04), location: min(1, f + 0.08)),
                .init(color: .white.opacity(o * 0.6), location: 1)]
    }

    /// Sombra barata: um shape preto atrás, com sombra deslocada para baixo e opacidade animada.
    private var shadowLayer: some View {
        shape.fill(Color.black)
            .shadow(color: .black.opacity(NotchTheme.Surface.shadowOpacity),
                    radius: NotchTheme.Surface.shadowRadius, y: NotchTheme.Surface.shadowY)
            .opacity(state == .expanded ? 1 : 0)
    }
}

enum NotchFont {
    static let caption = Font.system(size: 10)
    static let label = Font.system(size: 11)
    static let body = Font.system(size: 12)
    static let title = Font.system(size: 14, weight: .semibold)
    static let display = Font.system(size: 34, weight: .light, design: .rounded)
}

// MARK: - StateView

struct StateView: View {
    let kind: LoadState
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        switch kind {
        case .idle, .loaded:
            EmptyView()
        default:
            HStack(spacing: NotchTheme.Spacing.m) {
                icon
                Text(text)
                    .font(NotchFont.label)
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(NotchFont.label.weight(.medium))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .padding(.horizontal, NotchTheme.Spacing.l)
                            .padding(.vertical, NotchTheme.Spacing.xs)
                            .background(Capsule().fill(NotchTheme.fillSelected))
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .loading:
            ProgressView().controlSize(.small).scaleEffect(0.7)
                .frame(width: 14, height: 14)
        case .offline:
            symbol("wifi.slash")
        case .noPermission:
            symbol("lock.fill")
        case .failed:
            symbol("exclamationmark.triangle.fill")
        case .idle, .loaded:
            EmptyView()
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(NotchFont.label)
            .foregroundStyle(NotchTheme.textSecondary)
    }

    private var text: String {
        if let message { return message }
        switch kind {
        case .loading: return "Carregando…"
        case .offline: return "Sem conexão"
        case .noPermission: return "Permissão necessária"
        case .failed(let m): return m
        case .idle, .loaded: return ""
        }
    }
}

// MARK: - Shimmer

struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.25), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

extension View {
    /// Skeleton animado (parado com Reduce Motion).
    func shimmer() -> some View { modifier(Shimmer()) }
}
