//
//  TimerViews.swift
//  MyOwnNotch
//
//  Timer estilo Focus/Break: régua deslizante para escolher os minutos e,
//  durante a contagem, uma barra de marcas que vão se apagando.
//

import SwiftUI

extension TimerMode {
    var tint: Color {
        switch self {
        case .focus: return Color(red: 1.0, green: 0.62, blue: 0.2)     // laranja
        case .rest:  return Color(red: 0.3, green: 0.85, blue: 0.75)    // turquesa
        }
    }
    var icon: String { self == .focus ? "flame.fill" : "cup.and.saucer.fill" }
}

// MARK: - Compact

struct TimerCompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.timerIsRunning ? vm.timerMode.icon : (vm.timerSeconds == 0 ? "checkmark.circle.fill" : "pause.circle.fill"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.timerMode.tint)
            Text(vm.timerSeconds == 0 && !vm.timerIsRunning ? "Concluído!" : vm.timerDisplay)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Expanded

struct TimerExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var tint: Color { vm.timerMode.tint }

    private var primaryTitle: String {
        if vm.timerIsRunning { return "Pausar" }
        return vm.timerIsIdle ? "Start Timer" : "Continuar"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Modos
            HStack(spacing: 6) {
                ForEach(TimerMode.allCases, id: \.self) { mode in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.setTimerMode(mode) } } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(vm.timerMode == mode ? mode.tint : .white.opacity(0.45))
                            .padding(.horizontal, 11).padding(.vertical, 3)
                            .background(Capsule().fill(vm.timerMode == mode ? mode.tint.opacity(0.2) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .opacity(vm.timerIsRunning && vm.timerMode != mode ? 0.4 : 1)
                }
            }

            // Régua (parado) ou barra de progresso (rodando)
            ZStack {
                if vm.timerIsIdle {
                    TimerRuler(minutes: Binding(get: { vm.timerPresetMinutes }, set: { vm.setTimerMinutes($0) }), tint: tint)
                        .transition(.opacity)
                } else {
                    TimerBurnBar(remaining: Double(vm.timerSeconds), total: Double(max(1, vm.timerPresetMinutes * 60)), tint: tint)
                        .transition(.opacity)
                }
            }
            .frame(height: 50)

            // Ações + tempo
            HStack(spacing: 8) {
                Button {
                    if vm.timerIsRunning { vm.pauseTimer() } else { vm.startTimer() }
                } label: {
                    Text(primaryTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(tint.opacity(0.22)))
                }
                .buttonStyle(.plain)

                circleButton(vm.timerSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             active: vm.timerSoundEnabled) { vm.timerSoundEnabled.toggle() }
                circleButton("arrow.counterclockwise", active: false) { vm.resetTimer() }

                Spacer(minLength: 0)

                Text(vm.timerDisplay)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .contentTransition(.numericText())
                    .shadow(color: tint.opacity(vm.timerIsRunning ? 0.45 : 0), radius: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.timerIsIdle)
    }

    private func circleButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? tint : .white.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Régua deslizante

/// Régua de minutos: arraste para os lados; o valor fica sob o marcador central.
struct TimerRuler: View {
    @Binding var minutes: Int
    let tint: Color

    private let range = 1...120
    private let spacing: CGFloat = 6

    @State private var shown: Double = 25
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let half = Int(cx / spacing) + 2
                    let center = Int(shown.rounded())
                    for m in max(range.lowerBound, center - half)...min(range.upperBound, center + half) {
                        let x = cx + CGFloat(Double(m) - shown) * spacing
                        let dist = abs(Double(m) - shown)
                        let fade = max(0.12, 1 - dist / (Double(cx / spacing)))
                        let major = m % 5 == 0
                        let isCurrent = dist < 0.5
                        let h: CGFloat = isCurrent ? 24 : (major ? 18 : 12)
                        let color: Color = isCurrent ? .white : tint.opacity(fade)
                        let rect = CGRect(x: x - (isCurrent ? 1.25 : 0.75), y: size.height - 8 - h,
                                          width: isCurrent ? 2.5 : 1.5, height: h)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                        if major {
                            let label = Text("\(m)").font(.system(size: 10, weight: isCurrent ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isCurrent ? .white : tint.opacity(fade))
                            ctx.draw(label, at: CGPoint(x: x, y: size.height - 8 - 24 - 8))
                        }
                    }
                }
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                           .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                )

                // Marcador
                Triangle().fill(tint).frame(width: 9, height: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = shown }
                        let v = min(Double(range.upperBound), max(Double(range.lowerBound), dragStart! - Double(g.translation.width / spacing)))
                        shown = v
                        if Int(v.rounded()) != minutes { minutes = Int(v.rounded()) }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { shown = Double(minutes) }
                    }
            )
        }
        .onAppear { shown = Double(minutes) }
        .onChange(of: minutes) { new in
            if dragStart == nil { withAnimation(.easeOut(duration: 0.2)) { shown = Double(new) } }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Barra de marcas que se apagam

struct TimerBurnBar: View {
    let remaining: Double
    let total: Double
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let count = 70
            let step = size.width / CGFloat(count)
            let lit = Double(count) * remaining / total
            for i in 0..<count {
                let isLit = Double(i) + 0.5 < lit
                let isEdge = abs(Double(i) + 0.5 - lit) < 0.8
                let h: CGFloat = isEdge ? 30 : (i % 5 == 0 ? 22 : 16)
                let rect = CGRect(x: CGFloat(i) * step + step * 0.25, y: (size.height - h) / 2,
                                  width: step * 0.5, height: h)
                let color: Color = isEdge ? .white : (isLit ? tint.opacity(0.95) : Color.white.opacity(0.12))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .animation(.linear(duration: 1), value: remaining)
    }
}
