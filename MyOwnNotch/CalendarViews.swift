//
//  CalendarViews.swift
//  MyOwnNotch
//
//  Módulo de calendário: próxima reunião, lista do dia e estados de permissão.
//

import SwiftUI
import AppKit

// MARK: - Helpers

private enum CalendarFormat {
    static func range(_ e: CalendarEvent) -> String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(e.start.formatted(f)) – \(e.end.formatted(f))"
    }

    /// "agora", "em 5 min", "em 2 h 10 min", "em 3 h".
    static func relative(_ e: CalendarEvent, now: Date) -> String {
        if e.start <= now { return "agora" }
        let minutes = max(1, Int((e.start.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "em \(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "em \(h) h" : "em \(h) h \(m) min"
    }

    static func color(_ e: CalendarEvent) -> Color {
        e.colorHex.map { Color(hex: $0) } ?? NotchTheme.accent(for: .calendar)
    }
}

private let calendarSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

private func openSystemSettings(_ urlString: String) {
    if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
}

/// Texto relativo que se atualiza sozinho.
private struct RelativeTimeText: View {
    let event: CalendarEvent
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            Text(CalendarFormat.relative(event, now: ctx.date))
        }
    }
}

// MARK: - Estado de acesso

/// Resolve o que mostrar quando não há dados: desativado, sem permissão, erro ou vazio.
private struct CalendarGate<Content: View>: View {
    @ObservedObject var calendar: CalendarService
    @AppStorage(SettingsKey.calendarEnabled) private var enabled = false
    var compact = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if !enabled {
            StateView(kind: .noPermission,
                      message: compact ? "Calendário desativado" : "O calendário está desativado. Ative para ver suas reuniões.",
                      actionTitle: compact ? nil : "Ativar") {
                enabled = true
                calendar.start()
                calendar.requestAccess()
            }
        } else {
            switch calendar.authorization {
            case .noPermission:
                StateView(kind: .noPermission,
                          message: compact ? "Sem acesso ao Calendário" : "Sem acesso ao Calendário. Libere nos Ajustes do Sistema.",
                          actionTitle: compact ? nil : "Abrir Ajustes do Sistema") {
                    openSystemSettings(calendarSettingsURL)
                }
            case .idle:
                StateView(kind: .noPermission,
                          message: "Permita o acesso para ver suas reuniões",
                          actionTitle: compact ? nil : "Permitir") {
                    calendar.requestAccess()
                }
            case .failed(let m):
                StateView(kind: .failed(m), actionTitle: compact ? nil : "Tentar de novo") { calendar.refresh() }
            case .loading:
                StateView(kind: .loading)
            case .offline, .loaded:
                content()
            }
        }
    }
}

// MARK: - Compact

struct CalendarCompactView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        CalendarCompactBody(calendar: vm.calendar)
    }
}

private struct CalendarCompactBody: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        CalendarGate(calendar: calendar, compact: true) {
            if let e = calendar.nextEvent {
                HStack(spacing: NotchTheme.Spacing.m) {
                    Capsule().fill(CalendarFormat.color(e)).frame(width: 3, height: 16)
                    Text(e.title)
                        .font(NotchFont.body.weight(.semibold))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1)
                    RelativeTimeText(event: e)
                        .font(NotchFont.label)
                        .foregroundStyle(NotchTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: NotchTheme.Spacing.s) {
                    Image(systemName: "calendar").font(NotchFont.body)
                    Text("Sem reuniões em breve").font(NotchFont.label)
                }
                .foregroundStyle(NotchTheme.textSecondary)
            }
        }
    }
}

// MARK: - Expanded

struct CalendarExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        CalendarExpandedBody(calendar: vm.calendar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarExpandedBody: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        CalendarGate(calendar: calendar) {
            if let next = calendar.nextEvent {
                HStack(alignment: .top, spacing: NotchTheme.Spacing.l) {
                    NextEventCard(event: next)
                        .frame(maxWidth: .infinity)
                    upcomingList(excluding: next)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                HStack(spacing: NotchTheme.Spacing.m) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(NotchFont.title)
                    Text("Sem reuniões nas próximas horas")
                        .font(NotchFont.body)
                }
                .foregroundStyle(NotchTheme.textSecondary)
            }
        }
    }

    private func upcomingList(excluding next: CalendarEvent) -> some View {
        let rest = calendar.upcoming.filter { $0.id != next.id }
        return VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
            Text("Depois")
                .font(NotchFont.caption.weight(.semibold))
                .foregroundStyle(NotchTheme.textTertiary)
            if rest.isEmpty {
                Text("Nada mais por hoje")
                    .font(NotchFont.label)
                    .foregroundStyle(NotchTheme.textSecondary)
            } else {
                ForEach(rest.prefix(3)) { UpcomingRow(event: $0) }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct NextEventCard: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.l) {
            Capsule().fill(CalendarFormat.color(event)).frame(width: 4)

            VStack(alignment: .leading, spacing: NotchTheme.Spacing.xs) {
                RelativeTimeText(event: event)
                    .font(NotchFont.caption.weight(.semibold))
                    .foregroundStyle(CalendarFormat.color(event))
                Text(event.title)
                    .font(NotchFont.title)
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(2)
                Text(CalendarFormat.range(event))
                    .font(NotchFont.label)
                    .monospacedDigit()
                    .foregroundStyle(NotchTheme.textSecondary)
                if let place = event.location {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(NotchFont.caption)
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let url = event.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Entrar", systemImage: "video.fill")
                            .font(NotchFont.label.weight(.semibold))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .padding(.horizontal, NotchTheme.Spacing.l)
                            .frame(minHeight: 28)
                            .background(Capsule().fill(CalendarFormat.color(event).opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .help("Entrar na videochamada")
                    .accessibilityLabel("Entrar na reunião \(event.title)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NotchTheme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous)
            .fill(NotchTheme.fillSubtle))
        .accessibilityElement(children: .contain)
    }
}

private struct UpcomingRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            Capsule().fill(CalendarFormat.color(event)).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(NotchFont.label.weight(.medium))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(1)
                Text(event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened)))
                    .font(NotchFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(NotchTheme.textTertiary)
            }
            Spacer(minLength: 0)
            if let url = event.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill")
                        .font(NotchFont.label)
                        .foregroundStyle(NotchTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Entrar na videochamada")
                .accessibilityLabel("Entrar em \(event.title)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
