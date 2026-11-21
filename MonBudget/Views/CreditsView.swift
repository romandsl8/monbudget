import SwiftUI
import SwiftData

/// Onglet « Crédits » : restant à rembourser de chaque crédit, d'après la mensualité et la date de fin.
/// Les crédits sont aussi des opérations : leurs mensualités comptent dans le budget.
struct CreditsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<BudgetEntry> { $0.isLoan }, sort: \BudgetEntry.name)
    private var loans: [BudgetEntry]
    @Query(sort: \BudgetEntry.name) private var allEntries: [BudgetEntry]
    @State private var editorTarget: LoanEditorTarget?
    @State private var showPicker = false
    @State private var pendingEdit: BudgetEntry?

    /// Dépenses existantes qui ne sont pas encore suivies comme crédit.
    private var candidates: [BudgetEntry] {
        allEntries.filter { $0.kind == .expense && !$0.isLoan }
    }

    /// Transforme une dépense existante en crédit ; ouvre le formulaire si la date de fin manque.
    private func adopt(_ entry: BudgetEntry) {
        entry.isLoan = true
        if entry.category.isEmpty { entry.category = "Crédit" }
        if entry.endDate == nil || entry.frequency != .monthly {
            // Le formulaire s'ouvre une fois la liste refermée (voir onDismiss).
            pendingEdit = entry
        }
        showPicker = false
    }

    enum LoanEditorTarget: Identifiable {
        case new
        case edit(BudgetEntry)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let entry): "\(entry.persistentModelID.hashValue)"
            }
        }

        var entry: BudgetEntry? {
            if case .edit(let entry) = self { entry } else { nil }
        }
    }

    private struct Totals {
        var remaining: Decimal = 0
        var monthly: Decimal = 0
        var activeCount = 0
        var lastDate: Date?
    }

    private func makeTotals() -> Totals {
        var totals = Totals()
        for loan in loans {
            guard let status = loan.loanStatus(), !status.isFinished else { continue }
            totals.remaining += status.remainingAmount
            if loan.isActive { totals.monthly += loan.amount }
            totals.activeCount += 1
            if let last = status.lastDate, last > (totals.lastDate ?? .distantPast) {
                totals.lastDate = last
            }
        }
        return totals
    }

    var body: some View {
        let totals = makeTotals()
        List {
            if !loans.isEmpty {
                Section {
                    VStack(spacing: 6) {
                        Text("Restant à rembourser")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Money.format(totals.remaining))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(totalsDetail(totals))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Mes crédits") {
                    ForEach(loans) { loan in
                        Button {
                            editorTarget = .edit(loan)
                        } label: {
                            LoanRow(loan: loan)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(loans[index]) }
                    }
                }
            }
        }
        .overlay {
            if loans.isEmpty {
                ContentUnavailableView {
                    Label("Aucun crédit", systemImage: "building.columns")
                } description: {
                    Text("Ajoutez un crédit avec sa mensualité et sa date de fin : l'appli calcule ce qu'il reste à rembourser. Vous pouvez aussi marquer une opération existante comme crédit.")
                } actions: {
                    if !candidates.isEmpty {
                        Button("Choisir une dépense enregistrée") { showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Saisir un nouveau crédit") { editorTarget = .new }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Crédits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Choisir une dépense enregistrée", systemImage: "list.bullet") { showPicker = true }
                        .disabled(candidates.isEmpty)
                    Button("Saisir un nouveau crédit", systemImage: "square.and.pencil") { editorTarget = .new }
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                EntryEditorView(entry: target.entry, presetLoan: true)
            }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            if let entry = pendingEdit {
                pendingEdit = nil
                editorTarget = .edit(entry)
            }
        }) {
            NavigationStack {
                ExpensePickerView(candidates: candidates, onPick: adopt)
            }
        }
    }

    private func totalsDetail(_ totals: Totals) -> String {
        var text = "\(Money.format(totals.monthly)) de mensualités par mois"
        if let last = totals.lastDate {
            text += "\ndernier crédit terminé en " + last.formatted(.dateTime.month(.wide).year())
        }
        return text
    }
}

/// Liste des dépenses déjà saisies, celles de la catégorie « Crédit » en premier.
private struct ExpensePickerView: View {
    let candidates: [BudgetEntry]
    let onPick: (BudgetEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    private func isCreditCategory(_ entry: BudgetEntry) -> Bool {
        entry.category.localizedCaseInsensitiveContains("crédit")
            || entry.category.localizedCaseInsensitiveContains("credit")
            || entry.category.localizedCaseInsensitiveContains("prêt")
    }

    var body: some View {
        let credits = candidates.filter { isCreditCategory($0) }
        let others = candidates.filter { !isCreditCategory($0) }
        List {
            if !credits.isEmpty {
                Section("Catégorie Crédit") {
                    ForEach(credits) { row($0) }
                }
            }
            if !others.isEmpty {
                Section("Autres dépenses") {
                    ForEach(others) { row($0) }
                }
            }
        }
        .navigationTitle("Choisir une dépense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", role: .cancel) { dismiss() }
            }
        }
    }

    private func row(_ entry: BudgetEntry) -> some View {
        Button {
            onPick(entry)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(rowDetail(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(entry.amount))
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func rowDetail(_ entry: BudgetEntry) -> String {
        var text = entry.frequency.label
        if let end = entry.endDate {
            text += " · jusqu'en " + end.formatted(.dateTime.month(.wide).year())
        } else {
            text += " · date de fin à indiquer"
        }
        return text
    }
}

struct LoanRow: View {
    let loan: BudgetEntry

    var body: some View {
        let status = loan.loanStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.name)
                        .font(.headline)
                    Text("\(Money.format(loan.amount)) / mois")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if let status {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(status.isFinished ? "Terminé" : Money.format(status.remainingAmount))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(status.isFinished ? Color.green : Color.primary)
                        Text("restant dû")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status {
                ProgressView(value: status.progress)
                    .tint(.green)
                Text(detail(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Indiquez la date de la dernière mensualité pour calculer le restant dû.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .opacity(loan.isActive ? 1 : 0.5)
    }

    private func detail(_ status: LoanStatus) -> String {
        var parts: [String] = []
        parts.append("\(status.remainingPayments) mensualité\(status.remainingPayments > 1 ? "s" : "") restante\(status.remainingPayments > 1 ? "s" : "") sur \(status.totalPayments)")
        if let last = status.lastDate {
            parts.append("fin " + last.formatted(.dateTime.month(.wide).year()))
        }
        parts.append("déjà remboursé : " + Money.format(status.paidAmount))
        return parts.joined(separator: " · ")
    }
}
