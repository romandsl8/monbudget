import SwiftUI
import SwiftData

/// Création / modification d'une opération. Travaille sur un brouillon,
/// rien n'est enregistré tant qu'on n'appuie pas sur « Enregistrer ».
struct EntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: BudgetEntry?

    @State private var name: String
    @State private var amountText: String
    @State private var kind: EntryKind
    @State private var frequency: Frequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var category: String
    @State private var note: String
    @State private var isActive: Bool

    private static let suggestedCategories = [
        "Logement", "Énergie", "Assurance", "Téléphone & Internet", "Abonnements",
        "Transport", "Crédit", "Impôts", "Santé", "Salaire", "Épargne", "Autre",
    ]

    init(entry: BudgetEntry?) {
        self.entry = entry
        _name = State(initialValue: entry?.name ?? "")
        _amountText = State(initialValue: entry.map { Money.editableText($0.amount) } ?? "")
        _kind = State(initialValue: entry?.kind ?? .expense)
        _frequency = State(initialValue: entry?.frequency ?? .monthly)
        _startDate = State(initialValue: entry?.startDate ?? .now)
        _hasEndDate = State(initialValue: entry?.endDate != nil)
        _endDate = State(initialValue: entry?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _isActive = State(initialValue: entry?.isActive ?? true)
    }

    private var amount: Decimal? {
        guard let value = Money.parse(amountText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amount != nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(EntryKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Libellé (ex. Loyer, Netflix…)", text: $name)
                    .textInputAutocapitalization(.sentences)

                HStack {
                    TextField("Montant", text: $amountText)
                        .keyboardType(.decimalPad)
                    Text(Locale.current.currencySymbol ?? "€")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Échéance") {
                Picker("Fréquence", selection: $frequency) {
                    ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                }
                DatePicker(frequency == .once ? "Date" : "Première échéance",
                           selection: $startDate, displayedComponents: .date)
                if frequency != .once {
                    Toggle("Date de fin", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Dernière échéance", selection: $endDate,
                                   in: startDate..., displayedComponents: .date)
                    }
                }
            }

            Section("Détails") {
                HStack {
                    TextField("Catégorie", text: $category)
                    Menu {
                        ForEach(Self.suggestedCategories, id: \.self) { suggestion in
                            Button(suggestion) { category = suggestion }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
                Toggle("Active", isOn: $isActive)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(entry == nil ? "Nouvelle opération" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", action: save)
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let finalEnd: Date? = (frequency != .once && hasEndDate) ? endDate : nil

        if let entry {
            entry.name = trimmedName
            entry.amount = amount
            entry.kind = kind
            entry.frequency = frequency
            entry.startDate = startDate
            entry.endDate = finalEnd
            entry.category = category
            entry.note = note
            entry.isActive = isActive
        } else {
            context.insert(BudgetEntry(
                name: trimmedName,
                amount: amount,
                kind: kind,
                frequency: frequency,
                startDate: startDate,
                endDate: finalEnd,
                category: category,
                note: note,
                isActive: isActive
            ))
        }
        dismiss()
    }
}
