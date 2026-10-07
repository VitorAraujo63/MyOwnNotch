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
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ghGreens[4])
            if vm.github.hasUsername {
                Text("\(vm.github.todayCount) hoje")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text("· \(vm.github.yearCount) em \(vm.github.yearLabel)")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
            } else {
                Text("GitHub").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            }
        }
    }
}

// MARK: - Expanded

struct GitHubExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var input = ""
    @State private var editing = false

    var body: some View {
        let gh = vm.github
        if !gh.hasUsername || editing {
            userForm
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(ghGreens[4])
                    Text("@\(gh.username)")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                    if let err = gh.errorMessage {
                        Text(err).font(.system(size: 9)).foregroundColor(.orange)
                    }
                    Spacer()
                    pillButton(gh.isLoading ? "ellipsis" : "arrow.clockwise") { gh.refresh() }
                    pillButton("pencil") { input = gh.username; editing = true }
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
            }
        }
    }

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
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
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
                .foregroundColor(big ? ghGreens[4] : .white)
            Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
        }
    }

    private func pillButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 22, height: 18)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private var userForm: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 20, weight: .light)).foregroundColor(ghGreens[4])
            Text("Seu usuário do GitHub")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
            HStack(spacing: 6) {
                TextField("username", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .frame(width: 180)
                    .onSubmit(save)
                ActionPill(icon: "checkmark", label: "Salvar", action: save)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { input = vm.github.username }
    }

    private func save() {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vm.github.setUsername(input)
        editing = false
    }
}
