//
//  LiveActivityViews.swift
//  MyOwnNotch
//
//  Conteúdo das "asas" do notch no estado idle: a Live Activity primária ocupa as
//  duas laterais (ícone à esquerda, valor à direita) e a secundária aparece como um
//  indicador mínimo ao lado do valor.
//

import SwiftUI

// MARK: - Aparência por atividade

extension LiveActivity {
    var tint: Color {
        switch self {
        case .privacy:     return .green
        case .timerEnding: return .red
        case .timer:       return Color(red: 1.0, green: 0.62, blue: 0.2)
        case .meeting:     return .teal
        case .media:       return .pink
        case .charging:    return .green
        case .capsLock:    return Color(red: 1.0, green: 0.88, blue: 0.5)
        case .stayAwake:   return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }

    var symbol: String {
        switch self {
        case .privacy:          return "video.fill"
        case .timerEnding, .timer: return "timer"
        case .meeting:          return "calendar"
        case .media:            return "music.note"
        case .charging:         return "bolt.fill"
        case .capsLock:         return "capslock.fill"
        case .stayAwake:        return "cup.and.saucer.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .privacy:          return "Câmera ou microfone em uso"
        case .timerEnding:      return "Timer terminando"
        case .timer:            return "Timer"
        case .meeting:          return "Reunião"
        case .media:            return "Mídia tocando"
        case .charging:         return "Carregando"
        case .capsLock:         return "Caps Lock ligado"
        case .stayAwake:        return "Mantendo o Mac acordado"
        }
    }
}

// MARK: - Asas

/// Asa esquerda: ícone/arte da atividade primária.
struct LiveActivityLeading: View {
    @EnvironmentObject var vm: NotchViewModel
    let activity: LiveActivity

    var body: some View {
        switch activity {
        case .privacy:
            if vm.privacy.cameraInUse { dot(.green) } else { dot(.orange) }
        case .timerEnding, .timer:
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activity.tint)
        case .meeting:
            dot(vm.calendar.nextEvent?.colorHex.map { Color(hex: $0) } ?? activity.tint, size: 8)
        case .media:
            Group {
                if let art = vm.mediaArtwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.textTertiary)
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .charging, .capsLock, .stayAwake:
            Image(systemName: activity.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activity.tint)
        }
    }

    private func dot(_ color: Color, size: CGFloat = 7) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Asa direita: valor da atividade primária + indicador da secundária.
struct LiveActivityTrailing: View {
    @EnvironmentObject var vm: NotchViewModel
    let activity: LiveActivity
    let secondary: LiveActivity?

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.xs) {
            value
            if let secondary {
                Circle()
                    .fill(secondary.tint)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var value: some View {
        switch activity {
        case .privacy:
            // Padrão do sistema: verde = câmera, laranja = microfone
            if vm.privacy.cameraInUse && vm.privacy.micInUse {
                Circle().fill(.orange).frame(width: 7, height: 7)
            } else {
                Color.clear.frame(width: 7, height: 7)
            }
        case .timerEnding, .timer:
            Text(vm.timerDisplay)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(activity.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .meeting:
            MeetingCountdownText(event: vm.calendar.nextEvent)
        case .media:
            AudioBarsView(bars: vm.audioBars, color: NotchTheme.textTertiary, barWidth: 2, maxHeight: 12)
        case .charging:
            Text("\(vm.batteryLevel)%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(activity.tint)
                .lineLimit(1)
        case .capsLock:
            Text("Caps")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activity.tint)
                .lineLimit(1)
        case .stayAwake:
            Text("Acordado")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activity.tint)
                .lineLimit(1)
        }
    }
}

/// "agora" quando a reunião já começou; senão "N min". Atualiza a cada 15 s.
struct MeetingCountdownText: View {
    let event: CalendarEvent?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            Text(label(at: ctx.date))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private func label(at now: Date) -> String {
        guard let event else { return "" }
        if event.start <= now { return "agora" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return "\(max(1, minutes)) min"
    }
}

// MARK: - Acessibilidade

extension NotchViewModel {
    /// Descrição falada do estado idle.
    var idleAccessibilityLabel: String {
        liveActivities.map(\.accessibilityName).joined(separator: ", ")
    }
}
