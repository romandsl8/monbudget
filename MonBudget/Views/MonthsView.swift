import SwiftUI
import SwiftData

/// Revenus, dépenses et budget restant mois par mois.
/// Écran large (déplié) : liste des mois et détail côte à côte. Écran étroit (plié) : navigation empilée.
struct MonthsView: View {
    @Query private var entries: [BudgetEntry]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: Date?
    private var account = AccountSettings()

    private func makeSummaries() -> [MonthSummary] {
        let engine = BalanceEngine(
            startingBalance: account.startingBalance,
            referenceDate: account.referenceDate,
            entries: entries
        )
        return engine.monthSummaries(around: .now, before: 2, after: 12)
    }

    private var currentMonth: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    var body: some View {
        let summaries = makeSummaries()
        NavigationSplitView {
            List(summaries, selection: $selection) { summary in
                MonthRow(summary: summary, isCurrent: summary.month == currentMonth)
            }
            .navigationTitle("Mois par mois")
        } detail: {
            if let summary = summaries.first(where: { $0.month == selection }) {
                MonthDetailView(summary: summary, isCurrent: summary.month == currentMonth)
            } else {
                ContentUnavailableView("Sélectionnez un mois", systemImage: "calendar")
            }
        }
        .onAppear {
            // Sur grand écran, on ouvre directement le mois en cours.
            if selection == nil && horizontalSizeClass == .regular {
                selection = currentMonth
            }
        }
    }
}

private func monthTitle(_ date: Date) -> String {
    date.formatted(.dateTime.month(.wide).year()).capitalized
}

struct MonthRow: View {
    let summary: MonthSummary
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(monthTitle(summary.month))
                        .font(.headline)
                    if isCurrent {
                        Text("En cours")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("+\(Money.format(summary.income))  ·  −\(Money.format(summary.expenses))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Reste")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Money.format(summary.remaining))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(summary.remaining < 0 ? Color.red : Color.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MonthDetailView: View {
    let summary: MonthSummary
    let isCurrent: Bool

    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("Budget restant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.format(summary.remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(summary.remaining < 0 ? Color.red : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("soit environ \(Money.format(summary.remainingPerDay)) par jour")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                LabeledContent("Revenus prévus") {
                    Text(Money.format(summary.income)).foregroundStyle(.green).monospacedDigit()
                }
                LabeledContent("Dépenses prévues") {
                    Text(Money.format(summary.expenses)).foregroundStyle(.red).monospacedDigit()
                }
            } footer: {
                Text("Budget restant = revenus − dépenses (prélèvements et opérations saisies) du mois. C'est ce qu'il vous reste pour les dépenses courantes.")
            }

            if !summary.expensesByCategory.isEmpty {
                Section("Dépenses par catégorie") {
                    ForEach(summary.expensesByCategory) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category)
                                Spacer()
                                Text(Money.format(item.total)).monospacedDigit()
                            }
                            ProgressView(value: share(of: item.total))
                                .tint(.red.opacity(0.7))
                        }
                    }
                }
            }

            Section("Opérations du mois") {
                if summary.occurrences.isEmpty {
                    Text("Aucune opération ce mois-ci").foregroundStyle(.secondary)
                }
                ForEach(summary.occurrences) { occurrence in
                    HStack {
                        Text(occurrence.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(occurrence.name)
                        Spacer()
                        Text(Money.format(occurrence.amount, signed: true))
                            .monospacedDigit()
                            .foregroundStyle(occurrence.amount < 0 ? Color.red : Color.green)
                    }
                    // Dans le mois en cours, les échéances déjà passées sont estompées.
                    .opacity(isCurrent && occurrence.date < startOfToday ? 0.5 : 1)
                }
            }
        }
        .navigationTitle(monthTitle(summary.month))
    }

    private func share(of total: Decimal) -> Double {
        let all = summary.expenses.doubleValue
        guard all > 0 else { return 0 }
        return min(1, total.doubleValue / all)
    }
}
