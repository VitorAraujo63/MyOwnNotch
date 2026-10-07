//
//  BatteryViews.swift
//  MyOwnNotch
//
//  Views do módulo de bateria (compact e expanded).
//

import SwiftUI

// MARK: - Compact Battery

struct BatteryCompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    var batteryColor: Color {
        if vm.batteryIsCharging { return Color(hue: 0.33, saturation: 0.8, brightness: 0.9) }
        if vm.batteryLevel <= 10 { return Color.red }
        if vm.batteryLevel <= 20 { return Color.orange }
        return .white
    }

    var batteryIcon: String {
        if vm.batteryIsCharging { return "battery.100.bolt" }
        if vm.batteryLevel > 75 { return "battery.100" }
        if vm.batteryLevel > 50 { return "battery.75" }
        if vm.batteryLevel > 25 { return "battery.50" }
        if vm.batteryLevel > 10 { return "battery.25" }
        return "battery.0"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: batteryIcon)
                .font(.system(size: 14))
                .foregroundColor(batteryColor)

            Text("\(vm.batteryLevel)%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if vm.batteryIsCharging {
                Text("⚡")
                    .font(.system(size: 9))
            }
        }
    }
}

// MARK: - Expanded Battery

struct BatteryExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var d: BatteryDetails { vm.batteryDetails }

    private var accent: Color {
        if d.isCharging || (vm.batteryIsCharging && d.isFullyCharged) { return Color(red: 0.25, green: 0.88, blue: 0.5) }
        if vm.batteryLevel <= 10 { return Color(red: 1, green: 0.3, blue: 0.3) }
        if vm.batteryLevel <= 20 { return .orange }
        if d.lowPowerMode { return .yellow }
        return .white
    }

    private var statusText: String {
        if d.isFullyCharged && d.isPlugged { return "Carregada" }
        if d.isCharging { return "Carregando" }
        if d.isPlugged { return "Na tomada" }
        return "Na bateria"
    }

    private var timeText: String? {
        guard let m = d.timeMinutes else { return nil }
        let t = m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))min" : "\(m) min"
        return d.isCharging ? "\(t) para completar" : "\(t) restantes"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Anel de carga
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(vm.batteryLevel) / 100)
                    .stroke(AngularGradient(colors: [accent.opacity(0.55), accent], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * Double(vm.batteryLevel) / 100)),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.4), radius: 5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: vm.batteryLevel)
                VStack(spacing: 0) {
                    Text("\(vm.batteryLevel)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white).contentTransition(.numericText())
                    Text("%").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.45)).offset(y: -2)
                }
                if d.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)).foregroundColor(accent)
                        .offset(y: 24)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 8) {
                // Estado + tempo
                HStack(spacing: 6) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accent == .white ? .white : accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((accent == .white ? Color.white : accent).opacity(0.15)))
                    if d.lowPowerMode {
                        Label("Econômico", systemImage: "leaf.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.yellow)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.yellow.opacity(0.14)))
                    }
                    if let t = timeText {
                        Text(t).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }

                // Grade de métricas
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    BatteryTile(icon: "bolt.horizontal.fill", tint: .yellow,
                                value: d.watts > 0.05 ? String(format: "%.1f W", d.watts) : "—",
                                label: d.isCharging ? "Entrada" : "Consumo")
                    BatteryTile(icon: "heart.fill", tint: healthTint,
                                value: d.healthPercent.map { "\($0)%" } ?? "—", label: "Saúde")
                    BatteryTile(icon: "arrow.triangle.2.circlepath", tint: .cyan,
                                value: d.cycles.map { "\($0)" } ?? "—",
                                label: d.designCycles.map { "Ciclos / \($0)" } ?? "Ciclos")
                    BatteryTile(icon: "waveform.path.ecg", tint: .purple,
                                value: d.voltage.map { String(format: "%.2f V", $0) } ?? "—", label: "Tensão")
                    BatteryTile(icon: "battery.100", tint: .green,
                                value: capacityText, label: "Capacidade")
                    thirdTile
                }
            }
        }
        .onAppear { vm.fetchBatteryInfo() }
    }

    private var healthTint: Color {
        guard let h = d.healthPercent else { return .gray }
        return h >= 85 ? .green : (h >= 75 ? .orange : .red)
    }

    private var capacityText: String {
        guard let c = d.currentMAh, let f = d.fullMAh else { return "—" }
        return "\(c) / \(f)"
    }

    /// Adaptador (na tomada) ou temperatura (quando o Mac informa)
    @ViewBuilder private var thirdTile: some View {
        if let w = d.adapterWatts {
            BatteryTile(icon: "powerplug.fill", tint: .green, value: "\(w) W", label: "Adaptador")
        } else if let t = d.temperature {
            BatteryTile(icon: "thermometer.medium", tint: .orange, value: String(format: "%.1f °C", t), label: "Temperatura")
        } else {
            BatteryTile(icon: d.isPlugged ? "powerplug.fill" : "powerplug", tint: .gray,
                        value: d.isPlugged ? "Conectado" : "Desconectado", label: "Energia")
        }
    }
}

struct BatteryTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold)).foregroundColor(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 8.5, weight: .medium)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Dot animado de carregamento

struct ChargingDot: View {
    let index: Int
    let color: Color
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever()
                    .delay(Double(index) * 0.15)
                ) {
                    opacity = 1.0
                }
            }
    }
}
