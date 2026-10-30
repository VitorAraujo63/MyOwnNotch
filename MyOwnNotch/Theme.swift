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
        case .none, .actions, .volume: return .white
        }
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
