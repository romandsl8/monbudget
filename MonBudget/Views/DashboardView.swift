import SwiftUI
import SwiftData
import Charts

/// Onglet « Mon budget » : solde actuel (modifiable), reste à dépenser sur 1 mois,
/// échéances à venir à pointer.
struct DashboardView: View {
    @Query private var entries: [BudgetEntry]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showBalanceEditor = false
    @State private var chosenDate: Date = {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: .now)
        return interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? .now
    }()
    private var account = AccountSettings()

    /// Solde prévu à la fin du jour choisi : solde actuel + échéances non pointées jusqu'à ce jour.
    private func datedBalanceCard() -> some View {
        let engine = BalanceEngine(
            startingBalance: account.startingBalance,
            referenceDate: account.referenceDate,
            entries: entries
        )
        let pending = engine.checklist(through: chosenDate).filter { !$0.isCleared }
        let balance = account.startingBalance + pending.total
        let count = pending.count
        return VStack(alignment: .leading, spacing: 6) {
            DatePicker("Mon solde le", selection: $chosenDate,
                       in: Calendar.current.startOfDay(for: .now)...,
                       displayedComponents: .date)
                .font(.subheadline)
            Text(Money.format(balance))
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Color.red : Color.primary)
                .contentTransition(.numericText())
            Text(count == 0
                 ? "aucune opération d'ici là"
                 : "\(count) opération\(count > 1 ? "s" : "") à venir d'ici là (\(Money.format(pending.total, signed: true)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
        .animation(.default, value: chosenDate)
    }

    private struct UpcomingItem: Identifiable {
        let occurrence: Occurrence
        let balanceAfter: Decimal?   // nil si l'échéance est pointée
        let isOverdue: Bool
        var id: String { occurrence.id }
    }

    /// Toutes les valeurs affichées, calculées une seule fois par rendu.
    private struct Snapshot {
        let balance: Decimal
        let leftToSpend: Decimal
        let horizonEnd: Date
        let pendingIncome: Decimal
        let pendingExpenses: Decimal
        let month: MonthSummary
        let lowest: BalancePoint?
        let points: [BalancePoint]
        let items: [UpcomingItem]
        let monthlyDebitsTotal: Decimal
        let monthlyDebitsCount: Int
        let upcomingDebitsCount: Int
        let upcomingOneOffTotal: Decimal
    }

    private func makeSnapshot() -> Snapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let horizonEnd = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        let engine = BalanceEngine(
            startingBalance: account.startingBalance,
            referenceDate: account.referenceDate,
            entries: entries
        )

        let checklist = engine.checklist(through: horizonEnd)
        let pending = checklist.filter { !$0.isCleared }

        var running = account.startingBalance
        var items: [UpcomingItem] = []
        for occurrence in checklist {
            if occurrence.isCleared {
                items.append(UpcomingItem(occurrence: occurrence, balanceAfter: nil, isOverdue: false))
            } else {
                running += occurrence.amount
                let overdue = occurrence.date < today
                items.append(UpcomingItem(occurrence: occurrence, balanceAfter: running, isOverdue: overdue))
            }
        }

        let points = engine.pendingProjection(from: today, through: horizonEnd)
        let incomes = pending.filter { $0.amount > 0 }
        let expenses = pending.filter { $0.amount < 0 }

        // Prélèvements mensuels encore en cours (actifs et pas terminés).
        var monthlyDebitsTotal: Decimal = 0
        var monthlyDebitsCount = 0
        for entry in entries where entry.isActive && entry.kind == .expense && entry.frequency == .monthly {
            if let end = entry.endDate, calendar.startOfDay(for: end) < today { continue }
            monthlyDebitsTotal += entry.amount
            monthlyDebitsCount += 1
        }

        // Dépenses ponctuelles parmi les prélèvements à venir.
        var oneOffIDs = Set<PersistentIdentifier>()
        for entry in entries where entry.frequency == .once {
            oneOffIDs.insert(entry.persistentModelID)
        }
        let upcomingOneOffTotal = -expenses.filter { oneOffIDs.contains($0.entryID) }.total

        return Snapshot(
            balance: account.startingBalance,
            leftToSpend: account.startingBalance + pending.total,
            horizonEnd: horizonEnd,
            pendingIncome: incomes.total,
            pendingExpenses: -expenses.total,
            month: engine.monthSummary(containing: today),
            lowest: points.min { $0.balance < $1.balance },
            points: points,
            items: items,
            monthlyDebitsTotal: monthlyDebitsTotal,
            monthlyDebitsCount: monthlyDebitsCount,
            upcomingDebitsCount: expenses.count,
            upcomingOneOffTotal: upcomingOneOffTotal
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
                    upcomingList(snapshot)
                    chart(snapshot)
                }
                .padding()
            }
        }
        .navigationTitle("Mon budget")
        .sheet(isPresented: $showBalanceEditor) {
            NavigationStack {
                BalanceEditorView(current: account.startingBalance) { newBalance in
                    account.startingBalance = newBalance
                    account.referenceDate = Calendar.current.startOfDay(for: .now)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Actions

    private func toggle(_ occurrence: Occurrence) {
        guard let entry = entries.first(where: { $0.persistentModelID == occurrence.entryID }) else { return }
        let nowCleared = !occurrence.isCleared
        let delta = nowCleared ? occurrence.amount : -occurrence.amount
        withAnimation {
            entry.setCleared(nowCleared, on: occurrence.date)
            account.startingBalance = account.startingBalance + delta
        }
    }

    // MARK: - Sections

    private func summary(_ s: Snapshot) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 14) {
                Button {
                    showBalanceEditor = true
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Solde actuel")
                            Image(systemName: "pencil.circle.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(Money.format(s.balance))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(s.balance < 0 ? Color.red : Color.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Modifier le solde")

                Divider()

                VStack(spacing: 4) {
                    Text("Reste à dépenser d'ici le \(s.horizonEnd.formatted(.dateTime.day().month(.wide)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(Money.format(s.leftToSpend))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(s.leftToSpend < 0 ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("+\(Money.format(s.pendingIncome)) à recevoir · −\(Money.format(s.pendingExpenses)) à payer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.thinMaterial, in: .rect(cornerRadius: 20))

            datedBalanceCard()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                StatCard(
                    title: "Budget restant de \(s.month.month.formatted(.dateTime.month(.wide)))",
                    value: Money.format(s.month.remaining),
                    detail: "tous les revenus − toutes les dépenses du mois",
                    isNegative: s.month.remaining < 0
                )
                StatCard(
                    title: "Prélèvements mensuels",
                    value: Money.format(s.monthlyDebitsTotal),
                    detail: s.monthlyDebitsCount <= 1
                        ? "\(s.monthlyDebitsCount) prélèvement chaque mois"
                        : "\(s.monthlyDebitsCount) prélèvements chaque mois"
                )
                StatCard(
                    title: "Prélèvements à venir",
                    value: Money.format(s.pendingExpenses),
                    detail: upcomingDebitsDetail(s)
                )
                if let low = s.lowest {
                    StatCard(
                        title: "Point bas (1 mois)",
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
            Text("Évolution prévue sur 1 mois")
                .font(.headline)
            Chart {
                ForEach(s.points) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Solde", point.balance.doubleValue)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(.linearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
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
            .frame(minHeight: 200)
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private func upcomingList(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("À venir")
                .font(.headline)
            Text("Cochez une opération quand elle est passée sur votre compte : elle est reportée dans le solde actuel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            if s.items.isEmpty {
                ContentUnavailableView(
                    "Aucune échéance",
                    systemImage: "calendar",
                    description: Text("Ajoutez vos prélèvements et revenus dans l'onglet Opérations.")
                )
            } else {
                ForEach(s.items) { item in
                    upcomingRow(item)
                    Divider()
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private func upcomingRow(_ item: UpcomingItem) -> some View {
        let occurrence = item.occurrence
        let cleared = occurrence.isCleared
        return HStack(alignment: .center, spacing: 10) {
            Button {
                toggle(occurrence)
            } label: {
                Image(systemName: cleared ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(cleared ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cleared ? "Pointée" : "À pointer")

            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.name)
                    .strikethrough(cleared)
                Text(dateLabel(item))
                    .font(.caption)
                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(occurrence.amount, signed: true))
                    .foregroundStyle(occurrence.amount < 0 ? Color.red : Color.green)
                if let after = item.balanceAfter {
                    Text(Money.format(after))
                        .font(.caption)
                        .foregroundStyle(after < 0 ? Color.red : Color.secondary)
                }
            }
            .monospacedDigit()
        }
        .padding(.vertical, 8)
        .opacity(cleared ? 0.5 : 1)
    }

    private func upcomingDebitsDetail(_ s: Snapshot) -> String {
        let count = s.upcomingDebitsCount <= 1
            ? "\(s.upcomingDebitsCount) prélèvement d'ici 1 mois"
            : "\(s.upcomingDebitsCount) prélèvements d'ici 1 mois"
        guard s.upcomingOneOffTotal > 0 else { return count }
        return count + ", dont \(Money.format(s.upcomingOneOffTotal)) ponctuels"
    }

    private func dateLabel(_ item: UpcomingItem) -> String {
        let date = item.occurrence.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if item.occurrence.isCleared { return date + " · pointée" }
        if item.isOverdue { return date + " · pas encore passée" }
        return date
    }
}

/// Saisie rapide du solde affiché par la banque.
private struct BalanceEditorView: View {
    let current: Decimal
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Solde", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focused)
                        .font(.title2.monospacedDigit())
                    Text(Locale.current.currencySymbol ?? "€")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tapez le solde affiché par votre banque aujourd'hui. Les opérations prévues jusqu'à aujourd'hui sont considérées comme déjà passées.")
            }
        }
        .navigationTitle("Solde actuel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    if let value = Money.parse(text) {
                        onSave(value)
                        dismiss()
                    }
                }
                .disabled(Money.parse(text) == nil)
            }
        }
        .onAppear {
            text = Money.editableText(current)
            focused = true
        }
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
                .foregroundStyle(isNegative ? Color.red : Color.primary)
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
