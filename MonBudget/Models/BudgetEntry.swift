import Foundation
import SwiftData

/// Sens de l'opération.
enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: Self { self }

    var label: String {
        switch self {
        case .expense: "Dépense"
        case .income: "Revenu"
        }
    }
}

/// Fréquence de répétition d'une opération.
enum Frequency: String, Codable, CaseIterable, Identifiable {
    case once
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var id: Self { self }

    var label: String {
        switch self {
        case .once: "Ponctuelle"
        case .weekly: "Chaque semaine"
        case .biweekly: "Toutes les 2 semaines"
        case .monthly: "Chaque mois"
        case .quarterly: "Chaque trimestre"
        case .yearly: "Chaque année"
        }
    }

    /// Pas de calendrier entre deux échéances (nil = une seule échéance).
    var step: (component: Calendar.Component, value: Int)? {
        switch self {
        case .once: nil
        case .weekly: (.day, 7)
        case .biweekly: (.day, 14)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
    }
}

/// Une opération : prélèvement récurrent, revenu récurrent ou opération ponctuelle.
/// Les enums sont stockés en texte brut pour rester compatibles SwiftData / CloudKit.
@Model
final class BudgetEntry {
    var name: String = ""
    var amount: Decimal = 0          // toujours positif, le sens est donné par `kind`
    var kindRaw: String = EntryKind.expense.rawValue
    var frequencyRaw: String = Frequency.monthly.rawValue
    var startDate: Date = Date.now   // première échéance
    var endDate: Date? = nil         // dernière échéance possible (incluse)
    var category: String = ""
    var note: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date.now
    /// Jours des échéances pointées (passées sur le compte).
    var clearedDates: [Date] = []

    init(
        name: String,
        amount: Decimal,
        kind: EntryKind,
        frequency: Frequency,
        startDate: Date,
        endDate: Date? = nil,
        category: String = "",
        note: String = "",
        isActive: Bool = true
    ) {
        self.name = name
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.category = category
        self.note = note
        self.isActive = isActive
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Montant signé : négatif pour une dépense, positif pour un revenu.
    var signedAmount: Decimal {
        kind == .income ? amount : -amount
    }

    /// Dates d'échéance (début de journée) strictement après `lower` et au plus tard `upper`.
    /// Les mois sont calculés depuis la date de départ à chaque fois : un prélèvement le 31
    /// tombe le 30 avril puis à nouveau le 31 mai (pas de dérive).
    func occurrenceDates(after lower: Date, through upper: Date, calendar: Calendar = .current) -> [Date] {
        guard isActive else { return [] }
        let start = calendar.startOfDay(for: startDate)
        var limit = calendar.startOfDay(for: upper)
        if let endDate {
            limit = min(limit, calendar.startOfDay(for: endDate))
        }
        let lowerDay = calendar.startOfDay(for: lower)
        guard start <= limit else { return [] }

        guard let step = frequency.step else {
            return start > lowerDay ? [start] : []
        }

        var result: [Date] = []
        var index = 0
        while index < 20_000 {
            guard let date = calendar.date(byAdding: step.component, value: step.value * index, to: start) else { break }
            if date > limit { break }
            if date > lowerDay { result.append(date) }
            index += 1
        }
        return result
    }

    /// L'échéance de ce jour a-t-elle été pointée ?
    func isCleared(on date: Date, calendar: Calendar = .current) -> Bool {
        clearedDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    /// Pointe ou dépointe l'échéance de ce jour.
    func setCleared(_ cleared: Bool, on date: Date, calendar: Calendar = .current) {
        var dates = clearedDates.filter { !calendar.isDate($0, inSameDayAs: date) }
        if cleared {
            dates.append(calendar.startOfDay(for: date))
        }
        clearedDates = dates
    }

    /// Prochaine échéance à partir d'aujourd'hui (inclus).
    func nextDate(from date: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let horizon = calendar.date(byAdding: .year, value: 5, to: today) else { return nil }
        return occurrenceDates(after: yesterday, through: horizon, calendar: calendar).first
    }
}
