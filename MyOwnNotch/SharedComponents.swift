//
//  SharedComponents.swift
//  MyOwnNotch
//
//  Componentes reutilizáveis em vários módulos.
//

import SwiftUI

// MARK: - Audio Bars

struct AudioBarsView: View {
    let bars: [CGFloat]
    let color: Color
    let barWidth: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: max(2, maxHeight * height))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeInOut(duration: 0.12), value: bars)
    }
}

// MARK: - Marquee Text

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width
            ZStack(alignment: .leading) {
                if needsScroll {
                    HStack(spacing: 30) {
                        Text(text).font(font).foregroundColor(color).fixedSize()
                        Text(text).font(font).foregroundColor(color).fixedSize()
                    }
                    .offset(x: offset)
                    .onAppear {
                        guard !isAnimating else { return }
                        isAnimating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.linear(duration: Double(textWidth + 30) / 30.0).repeatForever(autoreverses: false)) {
                                offset = -(textWidth + 30)
                            }
                        }
                    }
                    .onChange(of: text) { _ in offset = 0; isAnimating = false }
                } else {
                    Text(text).font(font).foregroundColor(color)
                }
            }
            .clipped()
            .background(
                Text(text).font(font).fixedSize().hidden()
                    .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width } })
            )
        }
    }
}

// MARK: - Gradient Text

struct GradientText: View {
    let text: String
    let font: Font
    let gradient: LinearGradient

    var body: some View {
        Text(text).font(font).overlay(gradient.mask(Text(text).font(font)))
    }
}

// MARK: - Pulsating Circle

struct PulsatingCircle: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8

    var body: some View {
        Circle().fill(color).scaleEffect(scale).opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.3; opacity = 0.3
                }
            }
    }
}

// MARK: - Weather Views

struct WeatherCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.weatherIcon).font(.system(size: 13)).foregroundColor(.yellow)
            Text(vm.weatherTemp).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct WeatherExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    /// Cores do ícone conforme a condição/horário
    private var iconColors: [Color] {
        let d = vm.weatherDesc.lowercased()
        if !vm.weatherIsDay && (d.contains("clear") || d.contains("sun")) { return [Color(white: 0.95), Color.indigo] }
        if d.contains("rain") || d.contains("shower") || d.contains("drizzle") { return [.cyan, .blue] }
        if d.contains("snow") { return [.white, .cyan] }
        if d.contains("cloud") || d.contains("overcast") || d.contains("mist") || d.contains("fog") { return [Color(white: 0.9), Color(white: 0.55)] }
        return [.yellow, .orange]
    }

    var body: some View {
        HStack(spacing: 14) {
            // Ícone + cidade
            VStack(spacing: 6) {
                Image(systemName: vm.weatherIcon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 42))
                    .foregroundStyle(LinearGradient(colors: iconColors, startPoint: .top, endPoint: .bottom))
                    .shadow(color: iconColors.last!.opacity(0.45), radius: 10, y: 3)
                    .frame(height: 50)
                HStack(spacing: 3) {
                    Image(systemName: "location.fill").font(.system(size: 7))
                    Text(vm.weatherLocationDisplay).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.55))
            }
            .frame(width: 96)

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 0.5).padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(vm.weatherTemp)
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.weatherDesc)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Label(vm.weatherHigh, systemImage: "arrow.up")
                            Label(vm.weatherLow, systemImage: "arrow.down")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(.white.opacity(0.45))
                    }
                }

                HStack(spacing: 6) {
                    WeatherChip(icon: "thermometer.medium", text: vm.weatherFeelsLike, tint: .orange)
                    WeatherChip(icon: "humidity.fill", text: vm.weatherHumidity, tint: .cyan)
                    WeatherChip(icon: "wind", text: vm.weatherWind, tint: .mint)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
                    TextField("Buscar CEP ou cidade", text: $vm.weatherSearchInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .onSubmit { vm.fetchWeather(location: vm.weatherSearchInput) }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
    }
}

struct WeatherChip: View {
    let icon: String; let text: String; let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundColor(tint)
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - System Monitor Views

struct SystemCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu").font(.system(size: 12)).foregroundColor(.cyan)
            Text(String(format: "%.0f%%", vm.cpuUsage)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct SystemExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SystemRingCard(title: "CPU", icon: "cpu", value: vm.cpuUsage, history: vm.cpuHistory,
                               colors: [.cyan, .blue])
                SystemRingCard(title: "GPU", icon: "display", value: vm.gpuUsage, history: vm.gpuHistory,
                               colors: [.pink, .purple])
                SystemRingCard(title: "Memória", icon: "memorychip", value: vm.ramUsage, history: vm.ramHistory,
                               colors: [.green, .mint])
            }

            // Disco em barra fina
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Disco").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(100, max(0, vm.storageUsedPercent)) / 100))
                    }
                }
                .frame(height: 5)
                Text(String(format: "%.0f / %.0f GB", vm.storageUsedGB, vm.storageTotalGB))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize()
            }
        }
        .onAppear { vm.fetchStorageStats() }
    }
}

/// Cartão com anel de progresso + sparkline do histórico
struct SystemRingCard: View {
    let title: String
    let icon: String
    let value: Double
    let history: [Double]
    let colors: [Color]

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.09), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, value)) / 100))
                    .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
                Text(String(format: "%.0f", value))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundColor(colors[0])
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                SparkLine(values: history, colors: colors)
                    .frame(height: 18)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

struct SparkLine: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [colors[0].opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))

                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step,
                    y: size.height - CGFloat(min(100, max(0, v)) / 100) * (size.height - 2) - 1)
        }
    }
}

// Componente visual para as barras de progresso (mantido para outros usos)
struct SystemGaugeRow: View {
    let title: String
    let icon: String
    let percentage: Double
    let detailText: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(100.0, max(0.0, percentage)) / 100.0))
                }
            }
            .frame(height: 6)
        }
    }
}

struct GaugeCircle: View {
    let label: String; let value: Double; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 4)
                Circle().trim(from: 0, to: value / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: value)
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }.frame(width: 54, height: 54)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.4))
        }
    }
}

struct ActionPill: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Volume Views

struct VolumeCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.currentVolume == 0 ? "speaker.slash.fill" : (vm.currentVolume < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                .font(.system(size: 12)).foregroundColor(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white).frame(width: geo.size.width * CGFloat(vm.currentVolume) / 100.0)
                }
            }.frame(width: 60, height: 5)
        }
    }
}

// MARK: - Terminal Views

struct TerminalCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal.fill").font(.system(size: 11)).foregroundColor(.green)
            Text(">_").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white)
        }
    }
}

struct TerminalExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        TerminalHostView(session: vm.terminal)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Crypto Views

struct CryptoLineGraph: View {
    let color: Color; let points: [CGFloat]
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let stepX = geo.size.width / CGFloat(points.count - 1)
                let maxY = points.max() ?? 1; let minY = points.min() ?? 0
                let range = max(maxY - minY, 1)
                for (i, p) in points.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - ((p - minY) / range) * geo.size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct CryptoRow: View {
    let symbol: String; let name: String; let value: String; let change: String; let color: Color; let points: [CGFloat]
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "triangle.fill").font(.system(size: 5)).foregroundColor(color)
                    Text(symbol).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                }
                Text(name).font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
            }.frame(width: 55, alignment: .leading)
            CryptoLineGraph(color: color, points: points).frame(height: 16)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                Text(change).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(color)
            }.frame(width: 120, alignment: .trailing).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct CryptoCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 12)).foregroundColor(.green)
            Text(vm.cryptoCoins.first?.price ?? "--").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct CryptoExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(vm.cryptoCoins, id: \.symbol) { coin in
                FinanceCard(coin: coin)
            }
        }
    }
}

struct FinanceCard: View {
    let coin: CryptoCoin

    private var tint: Color { coin.isPositive ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.38, blue: 0.4) }

    private var icon: String {
        switch coin.symbol {
        case "BTC": return "bitcoinsign"
        case "USD": return "dollarsign"
        case "EUR": return "eurosign"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private var changeText: String {
        guard let v = Double(coin.change.replacingOccurrences(of: "%", with: "")) else { return coin.change }
        return String(format: "%+.2f%%", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(coin.symbol).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    Text(coin.name).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.4))
                }
                Spacer(minLength: 0)
            }

            Text(coin.price)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 3) {
                Image(systemName: coin.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text(changeText).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))

            PriceSpark(points: coin.points, color: tint)
                .frame(maxHeight: .infinity)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.10), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

/// Gráfico de preço normalizado (min–max) com preenchimento em gradiente
struct PriceSpark: View {
    let points: [CGFloat]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                Path { p in
                    guard let f = pts.first, let l = pts.last else { return }
                    p.move(to: CGPoint(x: f.x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: l.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))

                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                if let last = pts.last {
                    Circle().fill(color).frame(width: 5, height: 5).position(last)
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard points.count > 1, let lo = points.min(), let hi = points.max() else { return [] }
        let range = max(hi - lo, 0.0001)
        let step = size.width / CGFloat(points.count - 1)
        return points.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: size.height - 3 - ((v - lo) / range) * (size.height - 6))
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
