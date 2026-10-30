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
        .motionAnimation(.easeInOut(duration: 0.12), value: bars)
    }
}

// MARK: - Marquee Text

/// Texto que rola quando não cabe. Reinicia ao mudar o texto (`.id(text)`) e fica
/// estático (truncado) com Reduce Motion.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        MarqueeContent(text: text, font: font, color: color)
            .id(text)
    }
}

private struct MarqueeContent: View {
    let text: String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width && !reduceMotion
            ZStack(alignment: .leading) {
                if needsScroll {
                    HStack(spacing: 30) {
                        Text(text).font(font).foregroundColor(color).fixedSize()
                        Text(text).font(font).foregroundColor(color).fixedSize()
                    }
                    .offset(x: offset)
                    .onAppear(perform: startScrolling)
                    .onDisappear {
                        scrollTask?.cancel()
                        withAnimation(.linear(duration: 0)) { offset = 0 }  // interrompe o repeatForever
                    }
                } else {
                    Text(text).font(font).foregroundColor(color).lineLimit(1)
                }
            }
            .clipped()
            .background(
                Text(text).font(font).fixedSize().hidden()
                    .background(GeometryReader { g in Color.clear.onAppear { textWidth = g.size.width } })
            )
        }
    }

    private func startScrolling() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: Double(textWidth + 30) / 30.0).repeatForever(autoreverses: false)) {
                offset = -(textWidth + 30)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8

    var body: some View {
        Circle().fill(color).scaleEffect(scale).opacity(opacity)
            .onAppear {
                guard !reduceMotion else { return }
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
            Image(systemName: vm.weatherIcon).symbolRenderingMode(.multicolor).font(.system(size: 13))
            Text(vm.weatherTemp).font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clima: \(vm.weatherTemp), \(vm.weatherDesc)")
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
        HStack(spacing: 10) {
            Group {
                if vm.weatherForecast.isEmpty && vm.weatherStatus == .loading {
                    currentCard.shimmer()
                } else {
                    currentCard
                }
            }
            .frame(width: 168)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    WeatherChip(icon: "thermometer.medium", text: vm.weatherFeelsLike, tint: .orange)
                    WeatherChip(icon: "humidity.fill", text: vm.weatherHumidity, tint: .cyan)
                    WeatherChip(icon: "wind", text: vm.weatherWind, tint: .mint)
                    Spacer(minLength: 0)
                }

                forecastArea
                    .frame(maxHeight: .infinity)

                if !vm.weatherForecast.isEmpty, needsRetry {
                    StateView(kind: vm.weatherStatus, actionTitle: "Tentar de novo") { vm.fetchWeather() }
                }

                searchBar
            }
        }
    }

    private var needsRetry: Bool {
        switch vm.weatherStatus {
        case .offline, .failed: return true
        default: return false
        }
    }

    /// Previsão, skeleton (carregando) ou estado de erro com "Tentar de novo".
    @ViewBuilder private var forecastArea: some View {
        if !vm.weatherForecast.isEmpty {
            HStack(spacing: NotchTheme.Spacing.m) {
                ForEach(vm.weatherForecast) { ForecastCard(day: $0) }
            }
        } else if needsRetry || vm.weatherStatus == .noPermission {
            StateView(kind: vm.weatherStatus, actionTitle: "Tentar de novo") { vm.fetchWeather() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: NotchTheme.Spacing.m) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
                        .fill(NotchTheme.fillSubtle)
                }
            }
            .shimmer()
        }
    }

    // Cartão principal: ícone, temperatura, condição e cidade
    private var currentCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill").font(.system(size: 7))
                    Text(vm.weatherLocationDisplay).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(NotchTheme.textTertiary)

                Text(vm.weatherTemp)
                    .font(NotchFont.display)
                    .foregroundStyle(NotchTheme.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7).lineLimit(1)

                Text(vm.weatherDesc)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(vm.weatherHigh, systemImage: "arrow.up")
                    Label(vm.weatherLow, systemImage: "arrow.down")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTheme.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: vm.weatherIcon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 34))
                .foregroundStyle(LinearGradient(colors: iconColors, startPoint: .top, endPoint: .bottom))
                .shadow(color: (iconColors.last ?? .gray).opacity(0.5), radius: 9, y: 3)
                .frame(width: 40)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
                .fill(LinearGradient(colors: [(iconColors.last ?? .gray).opacity(0.22), Color.white.opacity(0.05)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
        )
    }

    // Busca: botão discreto que vira campo de texto
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(NotchTheme.textTertiary)
            TextField("Buscar CEP ou cidade", text: $vm.weatherSearchInput)
                .textFieldStyle(PlainTextFieldStyle())
                .font(NotchFont.label)
                .accessibilityLabel("Buscar clima por CEP ou cidade")
                .foregroundStyle(NotchTheme.textPrimary)
                .onSubmit { vm.fetchWeather(location: vm.weatherSearchInput) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(NotchTheme.fillSubtle))
    }
}

struct ForecastCard: View {
    let day: WeatherDay
    var body: some View {
        VStack(spacing: 3) {
            Text(day.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(NotchTheme.textTertiary)
            Image(systemName: day.icon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17))
                .frame(height: 20)
            HStack(spacing: 4) {
                Text(day.high).foregroundStyle(NotchTheme.textPrimary)
                Text(day.low).foregroundStyle(NotchTheme.textTertiary)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NotchTheme.fillSubtle))
    }
}

struct WeatherChip: View {
    let icon: String; let text: String; let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundColor(tint)
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(NotchTheme.textSecondary)
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
            Text(String(format: "%.0f%%", vm.cpuUsage)).font(.system(size: 12, weight: .semibold)).foregroundStyle(NotchTheme.textPrimary)
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
                Text("Disco").font(.system(size: 10, weight: .semibold)).foregroundStyle(NotchTheme.textSecondary)
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
                    .foregroundStyle(NotchTheme.textTertiary)
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
                    .foregroundStyle(NotchTheme.textPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: icon).font(.system(size: 8, weight: .bold)).foregroundColor(colors[0])
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(NotchTheme.textSecondary)
                        .lineLimit(1)
                }
                SparkLine(values: history, colors: colors)
                    .frame(height: 18)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous).fill(NotchTheme.fillSubtle))
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
                    .foregroundStyle(NotchTheme.textSecondary)
                Spacer()
                Text(detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchTheme.textTertiary)
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
                Circle().stroke(NotchTheme.fillSubtle, lineWidth: 4)
                Circle().trim(from: 0, to: value / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: value)
                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.textPrimary)
            }.frame(width: 54, height: 54)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(NotchTheme.textTertiary)
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
            .foregroundStyle(NotchTheme.textTertiary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(NotchTheme.fillSubtle))
        }.buttonStyle(.plain)
    }
}

// MARK: - Volume Views

struct VolumeCompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var icon: String {
        let v = vm.currentVolume
        if vm.systemMuted || v == 0 { return "speaker.slash.fill" }
        if v < 34 { return "speaker.wave.1.fill" }
        if v < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 18, alignment: .leading)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchTheme.fillSelected)
                    Capsule().fill(NotchTheme.textPrimary)
                        .frame(width: geo.size.width * CGFloat(vm.currentVolume) / 100.0)
                }
            }
            .frame(width: 90, height: 5)
            .motionAnimation(Motion.snappy, value: vm.currentVolume)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(vm.systemMuted ? "Mudo" : "\(vm.currentVolume)%")
    }
}

// MARK: - Terminal Views

struct TerminalCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal").font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
            Text("Terminal").font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
        }
    }
}

struct TerminalExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        TerminalHostView(session: vm.terminal)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.medium, style: .continuous).fill(Color.white.opacity(0.05)))
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
                    Text(symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(NotchTheme.textPrimary)
                }
                Text(name).font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
            }.frame(width: 55, alignment: .leading)
            CryptoLineGraph(color: color, points: points).frame(height: 16)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(NotchTheme.textPrimary)
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
            Text(vm.cryptoCoins.first?.price ?? "--").font(.system(size: 12, weight: .semibold)).foregroundStyle(NotchTheme.textPrimary)
        }
    }
}

struct CryptoExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    /// Os preços ainda são o placeholder "..." do ViewModel.
    private var hasData: Bool { vm.cryptoCoins.first?.price != "..." }

    private var needsRetry: Bool {
        switch vm.cryptoStatus {
        case .offline, .failed: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: NotchTheme.Spacing.m) {
            if !hasData && needsRetry {
                StateView(kind: vm.cryptoStatus, actionTitle: "Tentar de novo") { vm.fetchCrypto() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: NotchTheme.Spacing.m) {
                    ForEach(vm.cryptoCoins, id: \.symbol) { coin in
                        FinanceCard(coin: coin)
                    }
                }
                .shimmerIf(!hasData && vm.cryptoStatus == .loading)

                if hasData && needsRetry {
                    StateView(kind: vm.cryptoStatus, actionTitle: "Tentar de novo") { vm.fetchCrypto() }
                }
            }
        }
    }
}

extension View {
    /// Aplica o skeleton só quando `active`.
    @ViewBuilder func shimmerIf(_ active: Bool) -> some View {
        if active { shimmer() } else { self }
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
                    Text(coin.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(NotchTheme.textPrimary)
                    Text(coin.name).font(NotchFont.caption.weight(.medium)).foregroundStyle(NotchTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Text(coin.price)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.textPrimary)
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
            RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
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

// MARK: - Automação negada

/// Envolve conteúdo que depende de Automação (AppleScript). Se o macOS negou a permissão,
/// mostra o estado com atalho para Ajustes do Sistema > Privacidade > Automação.
struct AutomationGate<Content: View>: View {
    @EnvironmentObject var vm: NotchViewModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        if vm.automationDenied {
            StateView(kind: .noPermission,
                      message: "Automação negada. Libere em Privacidade > Automação.",
                      actionTitle: "Abrir Ajustes do Sistema") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            content()
        }
    }
}
