import SwiftUI
import SwiftData

/// Liste des opérations + détail.
/// NavigationSplitView affiche liste et détail côte à côte quand l'écran est large (déplié)
/// et se replie automatiquement en navigation empilée quand il est étroit (plié).
struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetEntry.name) private var entries: [BudgetEntry]
    @State private var selection: PersistentIdentifier?
    @State private var editorTarget: EditorTarget?

    enum EditorTarget: Identifiable {
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

    private var expenses: [BudgetEntry] { entries.filter { $0.kind == .expense } }
    private var incomes: [BudgetEntry] { entries.filter { $0.kind == .income } }
    private var selectedEntry: BudgetEntry? {
        entries.first { $0.persistentModelID == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !expenses.isEmpty {
                    Section("Dépenses") {
                        ForEach(expenses) { EntryRow(entry: $0) }
                            .onDelete { delete(expenses, at: $0) }
                    }
                }
                if !incomes.isEmpty {
                    Section("Revenus") {
                        ForEach(incomes) { EntryRow(entry: $0) }
                            .onDelete { delete(incomes, at: $0) }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune opération", systemImage: "tray")
                    } description: {
                        Text("Ajoutez vos prélèvements récurrents, votre salaire ou une dépense ponctuelle.")
                    } actions: {
                        Button("Ajouter une opération") { editorTarget = .new }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Opérations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ajouter", systemImage: "plus") { editorTarget = .new }
                }
            }
        } detail: {
            if let entry = selectedEntry {
                EntryDetailView(entry: entry) { editorTarget = .edit(entry) }
            } else {
                ContentUnavailableView("Sélectionnez une opération", systemImage: "list.bullet.rectangle")
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                EntryEditorView(entry: target.entry)
            }
        }
    }

    private func delete(_ source: [BudgetEntry], at offsets: IndexSet) {
        for index in offsets {
            let entry = source[index]
            if entry.persistentModelID == selection { selection = nil }
            context.delete(entry)
        }
    }
}

struct EntryRow: View {
    let entry: BudgetEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(entry.kind == .income ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(entry.signedAmount, signed: true))
                .monospacedDigit()
        }
        .opacity(entry.isActive ? 1 : 0.45)
    }

    private var subtitle: String {
        var parts = [entry.frequency.label]
        if !entry.isActive {
            parts.append("en pause")
        } else if let next = entry.nextDate() {
            parts.append("prochaine : " + next.formatted(.dateTime.day().month(.abbreviated)))
        } else {
            parts.append("terminée")
        }
        return parts.joined(separator: " · ")
    }
}

struct EntryDetailView: View {
    @Bindable var entry: BudgetEntry
    let onEdit: () -> Void

    private var nextDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let horizon = calendar.date(byAdding: .year, value: 3, to: today) else { return [] }
        return Array(entry.occurrenceDates(after: yesterday, through: horizon).prefix(12))
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Montant", value: Money.format(entry.signedAmount, signed: true))
                LabeledContent("Fréquence", value: entry.frequency.label)
                LabeledContent(entry.frequency == .once ? "Date" : "Première échéance",
                               value: entry.startDate.formatted(date: .long, time: .omitted))
                if let end = entry.endDate {
                    LabeledContent("Dernière échéance", value: end.formatted(date: .long, time: .omitted))
                }
                if !entry.category.isEmpty {
                    LabeledContent("Catégorie", value: entry.category)
                }
                Toggle("Active", isOn: $entry.isActive)
            }
            if !entry.note.isEmpty {
                Section("Note") { Text(entry.note) }
            }
            Section("Prochaines échéances") {
                if nextDates.isEmpty {
                    Text("Aucune échéance à venir").foregroundStyle(.secondary)
                }
                ForEach(nextDates, id: \.self) { date in
                    Text(date.formatted(date: .complete, time: .omitted))
                }
            }
        }
        .navigationTitle(entry.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifier", action: onEdit)
            }
        }
    }
}
