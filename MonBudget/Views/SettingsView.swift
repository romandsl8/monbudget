import SwiftUI
import SwiftData

/// Saisie du solde de départ. Sert aussi d'écran d'accueil au premier lancement.
struct SettingsView: View {
    var isOnboarding = false

    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [BudgetEntry]
    @State private var balanceText = ""
    @State private var date = Date.now
    @State private var saved = false
    private var account = AccountSettings()

    private var parsedBalance: Decimal? { Money.parse(balanceText) }

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    Text("Indiquez le solde de votre compte tel qu'il apparaît dans votre banque. L'application calculera ensuite votre solde au fil des prélèvements.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    TextField("Solde (ex. 1250,40 ou -80)", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                    Text(Locale.current.currencySymbol ?? "€")
                        .foregroundStyle(.secondary)
                }
                DatePicker("Constaté le", selection: $date, displayedComponents: .date)
            } header: {
                Text("Solde de départ")
            } footer: {
                Text("Les opérations prévues à cette date sont considérées comme déjà passées sur le compte.")
            }

            Section {
                Button(isOnboarding ? "Commencer" : "Enregistrer", action: save)
                    .disabled(parsedBalance == nil)
            } footer: {
                if saved && !isOnboarding {
                    Text("Solde enregistré.")
                }
            }

            if !isOnboarding {
                Section {
                    LabeledContent("Opérations enregistrées", value: "\(entries.count)")
                    LabeledContent("Solde actuel enregistré", value: Money.format(account.startingBalance))
                    LabeledContent("Au", value: account.referenceDate.formatted(date: .long, time: .omitted))
                } header: {
                    Text("Résumé")
                } footer: {
                    Text("Astuce : mettez régulièrement à jour ce solde avec celui de votre banque pour corriger les écarts (dépenses par carte, etc.).")
                }
            }
        }
        .navigationTitle(isOnboarding ? "Bienvenue" : "Réglages")
        .onAppear(perform: load)
    }

    private func load() {
        balanceText = account.isConfigured ? Money.editableText(account.startingBalance) : ""
        date = account.referenceDate
    }

    private func save() {
        guard let value = parsedBalance else { return }
        account.startingBalance = value
        account.referenceDate = Calendar.current.startOfDay(for: date)
        account.trackingStart = Calendar.current.startOfDay(for: date)
        saved = true
        if isOnboarding { dismiss() }
    }
}
