import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var entries: [BudgetEntry]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var horizon: Horizon = .quarter
    private var account = AccountSettings()

    enum Horizon: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .month: "30 jours"
            case .quarter: "3 mois"
            case .year: "1 an"
            }
        }
    }

    /// Toutes les valeurs affichées, calculées une seule fois par rendu.
    private struct Snapshot {
        let today: Decimal
        let endOfMonth: Decimal
        let monthExpenses: Decimal
        let lowest: BalancePoint?
        let points: [BalancePoint]
        let upcoming: [(occurrence: Occurrence, balanceAfter: Decimal)]
    }

    private func makeSnapshot() -> Snapshot {
        let calendar = Calendar.current
        let now = Date.now
        let engine = BalanceEngine(
            startingBalance: account.startingBalance,
            referenceDate: account.referenceDate,
            entries: entries
        )
        let todayBalance = engine.balance(on: now)

        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let lastDayOfMonth = monthInterval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? now
        let firstDayOfMonth = monthInterval?.start ?? now
        let dayBeforeMonth = calendar.date(byAdding: .day, value: -1, to: firstDayOfMonth) ?? now
        let monthExpenses = engine.occurrences(after: dayBeforeMonth, through: lastDayOfMonth)
            .filter { $0.amount < 0 }
            .total

        let points = engine.projection(from: now, days: horizon.rawValue)
        let horizonEnd = calendar.date(byAdding: .day, value: horizon.rawValue, to: now) ?? now

        var running = todayBalance
        let upcoming = engine.occurrences(after: now, through: horizonEnd).map { occurrence in
            running += occurrence.amount
            return (occurrence: occurrence, balanceAfter: running)
        }

        return Snapshot(
            today: todayBalance,
            endOfMonth: engine.balance(on: lastDayOfMonth),
            monthExpenses: -monthExpenses,
            lowest: points.min { $0.balance < $1.balance },
            points: points,
            upcoming: upcoming
        )
    }

    var body: some View {
        let snapshot = makeSnapshot()
        ScrollView {
            if horizontalSizeClass == .regular {
                // Écran large (déplié) : deux colonnes côte à côte.
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        summary(snapshot)
                        chart(snapshot)
                    }
                    .frame(maxWidth: .infinity)
                    upcomingList(snapshot)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                // Écran étroit (plié) : une colonne.
                VStack(spacing: 20) {
                    summary(snapshot)
                    chart(snapshot)
                    upcomingList(snapshot)
                }
                .padding()
            }
        }
        .navigationTitle("Mon budget")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Horizon", selection: $horizon) {
                    ForEach(Horizon.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Sections

    private func summary(_ s: Snapshot) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Solde aujourd'hui")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Money.format(s.today))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(s.today < 0 ? .red : .primary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.thinMaterial, in: .rect(cornerRadius: 20))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                StatCard(title: "Fin du mois", value: Money.format(s.endOfMonth), isNegative: s.endOfMonth < 0)
                StatCard(title: "Dépenses du mois", value: Money.format(s.monthExpenses))
                if let low = s.lowest {
                    StatCard(
                        title: "Point bas (\(horizon.label))",
                        value: Money.format(low.balance),
                        detail: low.date.formatted(.dateTime.day().month(.abbreviated)),
                        isNegative: low.balance < 0
                    )
                }
            }
        }
    }

    private func chart(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Évolution prévue")
                .font(.headline)
            Chart {
                ForEach(s.points) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Solde", point.balance.doubleValue)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(.linearGradient(
                        colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Solde", point.balance.doubleValue)
                    )
                    .interpolationMethod(.stepEnd)
                }
                RuleMark(y: .value("Zéro", 0))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(minHeight: 220)
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private func upcomingList(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("À venir")
                .font(.headline)
                .padding(.bottom, 8)
            if s.upcoming.isEmpty {
                ContentUnavailableView(
                    "Aucune échéance",
                    systemImage: "calendar",
                    description: Text("Ajoutez vos prélèvements dans l'onglet Opérations.")
                )
            } else {
                ForEach(s.upcoming, id: \.occurrence.id) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.occurrence.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(item.occurrence.name)
                            if !item.occurrence.category.isEmpty {
                                Text(item.occurrence.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Money.format(item.occurrence.amount, signed: true))
                                .foregroundStyle(item.occurrence.amount < 0 ? .red : .green)
                            Text(Money.format(item.balanceAfter))
                                .font(.caption)
                                .foregroundStyle(item.balanceAfter < 0 ? .red : .secondary)
                        }
                        .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    var isNegative = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(isNegative ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}
