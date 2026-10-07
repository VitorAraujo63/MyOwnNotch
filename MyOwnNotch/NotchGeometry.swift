//
//  NotchGeometry.swift
//  MyOwnNotch
//
//  Medidas do notch físico da tela e a forma (NotchShape) usada pela ilha:
//  topo rente à borda da tela, "orelhas" côncavas no topo e cantos
//  arredondados embaixo, como nas referências.
//

import SwiftUI
import AppKit

// MARK: - Medidas do hardware

struct NotchMetrics: Equatable {
    /// Largura do recorte físico da câmera (ou um valor padrão em Macs sem notch).
    var hardwareWidth: CGFloat
    /// Altura do recorte físico (ou da menu bar em Macs sem notch).
    var hardwareHeight: CGFloat
    var hasNotch: Bool

    static let fallback = NotchMetrics(hardwareWidth: 200, hardwareHeight: 24, hasNotch: false)

    /// Prefere a tela com notch; senão usa a tela principal.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func measure(_ screen: NSScreen?) -> NotchMetrics {
        guard let screen else { return .fallback }
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchMetrics(hardwareWidth: width.rounded(.up), hardwareHeight: inset, hasNotch: true)
        }
        // Sem notch: usa a altura real da menu bar
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(hardwareWidth: 200, hardwareHeight: max(menuBar, 24), hasNotch: false)
    }

    // MARK: Tamanho da ilha por estado

    /// Largura de cada "asa" visível ao lado do notch quando há mídia tocando.
    static let wingWidth: CGFloat = 38
    /// Altura da faixa de conteúdo abaixo do notch no estado compact.
    static let compactStripHeight: CGFloat = 32
    /// Altura da área de conteúdo no estado expanded (abaixo da linha do notch).
    static let expandedContentHeight: CGFloat = 150
    static let terminalContentHeight: CGFloat = 250

    func islandSize(for state: NotchState, mediaPlaying: Bool, module: NotchModule = .none) -> CGSize {
        switch state {
        case .idle:
            let wings = (mediaPlaying ? 2 * Self.wingWidth : 0)
            return CGSize(width: hardwareWidth + wings, height: hardwareHeight)
        case .compact:
            return CGSize(width: max(260, hardwareWidth + 60), height: hardwareHeight + Self.compactStripHeight)
        case .expanded:
            // Terminal ganha uma janela maior (~20% mais larga, bem mais alta)
            if module == .terminal || module == .agent {
                return CGSize(width: max(600, hardwareWidth + 380), height: hardwareHeight + Self.terminalContentHeight)
            }
            return CGSize(width: max(540, hardwareWidth + 332), height: hardwareHeight + Self.expandedContentHeight)
        }
    }

    // Raios da forma (topo = orelhas côncavas, base = cantos arredondados)
    func topRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle: return 6
        case .compact: return 8
        case .expanded: return 12
        }
    }

    func bottomRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle: return 10
        case .compact: return 16
        case .expanded: return 26
        }
    }

    /// Margem transparente da janela ao redor da ilha (espaço para a sombra não ser cortada).
    static let windowPadding: CGFloat = 22
}

// MARK: - Forma do Notch

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4, rect.height / 2)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Orelha esquerda (côncava)
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        // Lateral esquerda
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // Canto inferior esquerdo
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        // Base
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // Canto inferior direito
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        // Lateral direita
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Orelha direita (côncava)
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
