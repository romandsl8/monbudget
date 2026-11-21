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
    @State private var isLoan: Bool

    private static let suggestedCategories = [
        "Logement", "Énergie", "Assurance", "Téléphone & Internet", "Abonnements",
        "Transport", "Crédit", "Impôts", "Santé", "Salaire", "Épargne", "Autre",
    ]

    /// `presetLoan` : nouvelle opération créée depuis l'onglet Crédits.
    init(entry: BudgetEntry?, presetLoan: Bool = false) {
        self.entry = entry
        let loan = entry?.isLoan ?? presetLoan
        _isLoan = State(initialValue: loan)
        _name = State(initialValue: entry?.name ?? "")
        _amountText = State(initialValue: entry.map { Money.editableText($0.amount) } ?? "")
        _kind = State(initialValue: entry?.kind ?? .expense)
        _frequency = State(initialValue: entry?.frequency ?? .monthly)
        _startDate = State(initialValue: entry?.startDate ?? .now)
        _hasEndDate = State(initialValue: entry?.endDate != nil || loan)
        _endDate = State(initialValue: entry?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _category = State(initialValue: entry?.category ?? (loan ? "Crédit" : ""))
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
                if !isLoan {
                    Picker("Type", selection: $kind) {
                        ForEach(EntryKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                TextField(isLoan ? "Nom du crédit (ex. Prêt auto)" : "Libellé (ex. Loyer, Netflix…)", text: $name)
                    .textInputAutocapitalization(.sentences)

                HStack {
                    TextField(isLoan ? "Mensualité" : "Montant", text: $amountText)
                        .keyboardType(.decimalPad)
                    Text(Locale.current.currencySymbol ?? "€")
                        .foregroundStyle(.secondary)
                }
            }

            if isLoan {
                Section {
                    DatePicker("Première mensualité", selection: $startDate, displayedComponents: .date)
                    DatePicker("Dernière mensualité", selection: $endDate,
                               in: startDate..., displayedComponents: .date)
                    if let preview = loanPreview {
                        LabeledContent("Restant à rembourser", value: Money.format(preview.remainingAmount))
                        LabeledContent("Mensualités restantes", value: "\(preview.remainingPayments) / \(preview.totalPayments)")
                    }
                } header: {
                    Text("Échéancier")
                } footer: {
                    Text("Prélevé chaque mois le même jour que la première mensualité.")
                }
            } else {
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
                if kind == .expense {
                    Toggle("C'est un crédit", isOn: $isLoan.animation())
                }
                Toggle("Active", isOn: $isActive)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(entry == nil ? (isLoan ? "Nouveau crédit" : "Nouvelle opération") : "Modifier")
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

    /// Aperçu du restant dû pendant la saisie d'un crédit.
    private var loanPreview: LoanStatus? {
        guard let amount else { return nil }
        let draft = BudgetEntry(name: name, amount: amount, kind: .expense, frequency: .monthly,
                                startDate: startDate, endDate: endDate)
        return draft.loanStatus()
    }

    private func save() {
        guard let amount else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        // Un crédit est toujours une dépense mensuelle avec une date de fin.
        let finalKind: EntryKind = isLoan ? .expense : kind
        let finalFrequency: Frequency = isLoan ? .monthly : frequency
        let finalEnd: Date? = isLoan ? endDate : ((frequency != .once && hasEndDate) ? endDate : nil)

        let target: BudgetEntry
        if let entry {
            target = entry
        } else {
            target = BudgetEntry(name: trimmedName, amount: amount, kind: finalKind,
                                 frequency: finalFrequency, startDate: startDate)
            context.insert(target)
        }
        target.name = trimmedName
        target.amount = amount
        target.kind = finalKind
        target.frequency = finalFrequency
        target.startDate = startDate
        target.endDate = finalEnd
        target.category = category
        target.note = note
        target.isActive = isActive
        target.isLoan = isLoan
        dismiss()
    }
}
