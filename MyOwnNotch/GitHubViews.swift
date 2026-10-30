//
//  GitHubViews.swift
//  MyOwnNotch
//
//  Aba do GitHub: total de contribuições do ano, hoje, sequência e heatmap.
//

import SwiftUI

private let ghGreens: [Color] = [
    Color.white.opacity(0.08),
    Color(red: 0.06, green: 0.27, blue: 0.16),
    Color(red: 0.0, green: 0.43, blue: 0.20),
    Color(red: 0.15, green: 0.65, blue: 0.25),
    Color(red: 0.22, green: 0.83, blue: 0.33),
]

// MARK: - Compact

struct GitHubCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View { GitHubCompactContent(github: vm.github) }
}

private struct GitHubCompactContent: View {
    @ObservedObject var github: GitHubService
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(NotchFont.label.weight(.semibold))
                .foregroundStyle(ghGreens[4])
            if github.hasUsername {
                Text("\(github.todayCount) hoje")
                    .font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
                Text("· \(github.yearCount) em \(github.yearLabel)")
                    .font(NotchFont.label).foregroundStyle(NotchTheme.textTertiary)
            } else {
                Text("GitHub").font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
            }
        }
    }
}

// MARK: - Expanded

struct GitHubExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View { GitHubExpandedContent(github: vm.github) }
}

private struct GitHubExpandedContent: View {
    @ObservedObject var github: GitHubService
    @State private var input = ""
    @State private var editing = false

    var body: some View {
        let gh = github
        if !gh.hasUsername || editing {
            userForm
        } else {
            VStack(alignment: .leading, spacing: NotchTheme.Spacing.m) {
                HStack(spacing: NotchTheme.Spacing.s) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(NotchFont.caption.weight(.semibold)).foregroundStyle(ghGreens[4])
                        .accessibilityHidden(true)
                    Text("@\(gh.username)")
                        .font(NotchFont.label.weight(.semibold)).foregroundStyle(NotchTheme.textSecondary)
                    Spacer()
                    pillButton(gh.isLoading ? "ellipsis" : "arrow.clockwise", label: "Atualizar") { gh.refresh() }
                        .disabled(gh.isLoading)
                    pillButton("pencil", label: "Trocar usuário") { input = gh.username; editing = true }
                }

                if let err = gh.errorMessage, gh.days.isEmpty {
                    StateView(kind: Self.kind(for: err), message: err, actionTitle: "Tentar de novo") { gh.refresh() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                if let err = gh.errorMessage {
                    StateView(kind: Self.kind(for: err), message: err)
                }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        stat("\(gh.yearCount)", "em \(gh.yearLabel)", big: true)
                        stat("\(gh.todayCount)", "hoje")
                        stat("\(gh.streak)", gh.streak == 1 ? "dia seguido" : "dias seguidos")
                    }
                    .frame(width: 92, alignment: .leading)

                    heatmap(gh.days)
                }
                .redacted(reason: gh.isLoading && gh.days.isEmpty ? .placeholder : [])
                }
            }
        }
    }

    private static func kind(for error: String) -> LoadState {
        error.contains("conexão") ? .offline : .failed(error)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Heatmap

    private func heatmap(_ days: [GitHubDay]) -> some View {
        let weeks = Self.weeks(from: days, maxWeeks: 34)
        return HStack(alignment: .top, spacing: 2.5) {
            ForEach(weeks.indices, id: \.self) { w in
                VStack(spacing: 2.5) {
                    ForEach(0..<7, id: \.self) { d in
                        if let day = weeks[w][d] {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(ghGreens[min(4, max(0, day.level))])
                                .frame(width: 9, height: 9)
                                .help("\(day.count) em \(day.date)")
                                .accessibilityLabel("\(day.count) contribuições em \(day.date)")
                        } else {
                            Color.clear.frame(width: 9, height: 9)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Agrupa os dias em colunas de semana (domingo → sábado), como o GitHub.
    private static func weeks(from days: [GitHubDay], maxWeeks: Int) -> [[GitHubDay?]] {
        guard let first = days.first else { return [] }
        let f = dayParser
        let cal = Calendar(identifier: .gregorian)
        let offset = f.date(from: first.date).map { cal.component(.weekday, from: $0) - 1 } ?? 0
        var cells: [GitHubDay?] = Array(repeating: nil, count: offset) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        let all = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        return Array(all.suffix(maxWeeks))
    }

    // MARK: Peças

    private func stat(_ value: String, _ label: String, big: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: big ? 22 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(big ? ghGreens[4] : NotchTheme.textPrimary)
            Text(label).font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
        }
    }

    private func pillButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(NotchFont.caption.weight(.semibold))
                .foregroundStyle(NotchTheme.textSecondary)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(NotchTheme.fillSubtle))
        }
        .buttonStyle(HoverPressStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private var userForm: some View {
        VStack(spacing: NotchTheme.Spacing.m) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 20, weight: .light)).foregroundStyle(ghGreens[4])
                .accessibilityHidden(true)
            Text("Seu usuário do GitHub")
                .font(NotchFont.label.weight(.medium)).foregroundStyle(NotchTheme.textSecondary)
            HStack(spacing: NotchTheme.Spacing.s) {
                TextField("username", text: $input)
                    .textFieldStyle(.plain)
                    .font(NotchFont.body)
                    .foregroundStyle(NotchTheme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(NotchTheme.fillSelected))
                    .frame(width: 180)
                    .onSubmit(save)
                    .accessibilityLabel("Usuário do GitHub")
                ActionPill(icon: "checkmark", label: "Salvar", action: save)
            }
            if let err = github.errorMessage {
                StateView(kind: Self.kind(for: err), message: err)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { input = github.username }
    }

    private func save() {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        github.setUsername(input)
        editing = false
    }
}
