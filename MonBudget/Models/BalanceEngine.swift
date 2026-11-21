import Foundation
import SwiftData

/// Une échéance concrète d'une opération à une date donnée.
struct Occurrence: Identifiable, Hashable {
    let entryID: PersistentIdentifier
    let name: String
    let category: String
    let date: Date
    let amount: Decimal   // signé

    var id: String { "\(entryID.hashValue)|\(date.timeIntervalSinceReferenceDate)" }
}

/// Solde à la fin d'une journée.
struct BalancePoint: Identifiable {
    let date: Date
    let balance: Decimal
    var id: Date { date }
}

/// Revenus, dépenses et budget restant d'un mois civil.
struct MonthSummary: Identifiable {
    let month: Date              // premier jour du mois
    let daysInMonth: Int
    let occurrences: [Occurrence]

    var id: Date { month }

    var income: Decimal { occurrences.filter { $0.amount > 0 }.total }
    /// Total des dépenses, en valeur positive.
    var expenses: Decimal { -occurrences.filter { $0.amount < 0 }.total }
    /// Budget restant = revenus − dépenses prévues du mois.
    var remaining: Decimal { income - expenses }
    /// Budget restant réparti sur les jours du mois.
    var remainingPerDay: Decimal { daysInMonth > 0 ? remaining / Decimal(daysInMonth) : remaining }

    /// Dépenses regroupées par catégorie, de la plus grosse à la plus petite.
    var expensesByCategory: [CategoryTotal] {
        var totals: [String: Decimal] = [:]
        for occurrence in occurrences where occurrence.amount < 0 {
            let key = occurrence.category.isEmpty ? "Sans catégorie" : occurrence.category
            let current = totals[key] ?? 0
            totals[key] = current - occurrence.amount
        }
        var result: [CategoryTotal] = []
        for (category, total) in totals {
            result.append(CategoryTotal(category: category, total: total))
        }
        result.sort { lhs, rhs in lhs.total > rhs.total }
        return result
    }
}

struct CategoryTotal: Identifiable {
    let category: String
    let total: Decimal
    var id: String { category }
}

extension Array where Element == Occurrence {
    var total: Decimal { reduce(Decimal(0)) { $0 + $1.amount } }
}

/// Calcule le solde dynamique à partir du solde de départ et des opérations.
///
/// Convention : le solde de départ est celui constaté à la fin de `referenceDate`,
/// donc les échéances de ce jour-là sont considérées comme déjà passées.
struct BalanceEngine {
    let startingBalance: Decimal
    let referenceDate: Date
    let entries: [BudgetEntry]
    var calendar: Calendar = .current

    /// Échéances dont le jour est strictement après `start` et au plus tard le jour de `end`, triées.
    func occurrences(after start: Date, through end: Date) -> [Occurrence] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        guard upper > lower else { return [] }
        var result: [Occurrence] = []
        for entry in entries {
            let dates = entry.occurrenceDates(after: lower, through: upper, calendar: calendar)
            for date in dates {
                let occurrence = Occurrence(
                    entryID: entry.persistentModelID,
                    name: entry.name,
                    category: entry.category,
                    date: date,
                    amount: entry.signedAmount
                )
                result.append(occurrence)
            }
        }
        result.sort(by: Self.isOrderedBefore)
        return result
    }

    /// Par date, puis revenus avant dépenses le même jour.
    private static func isOrderedBefore(_ lhs: Occurrence, _ rhs: Occurrence) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.amount > rhs.amount
    }

    /// Solde à la fin de la journée `date` (passée ou future).
    func balance(on date: Date) -> Decimal {
        let ref = calendar.startOfDay(for: referenceDate)
        let day = calendar.startOfDay(for: date)
        if day >= ref {
            return startingBalance + occurrences(after: ref, through: day).total
        } else {
            return startingBalance - occurrences(after: day, through: ref).total
        }
    }

    /// Toutes les échéances du mois civil contenant `date` (indépendamment du solde de départ).
    func monthSummary(containing date: Date) -> MonthSummary {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: interval.start) else {
            return MonthSummary(month: date, daysInMonth: 30, occurrences: [])
        }
        let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        return MonthSummary(
            month: interval.start,
            daysInMonth: days,
            occurrences: occurrences(after: dayBefore, through: lastDay)
        )
    }

    /// Résumés de `before` mois avant à `after` mois après le mois de `date`.
    func monthSummaries(around date: Date, before: Int, after: Int) -> [MonthSummary] {
        (-before...after).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: date).map { monthSummary(containing: $0) }
        }
    }

    /// Un point par jour, de `start` à `start + days`.
    func projection(from start: Date, days: Int) -> [BalancePoint] {
        let first = calendar.startOfDay(for: start)
        guard days > 0, let last = calendar.date(byAdding: .day, value: days, to: first) else { return [] }

        var byDay: [Date: Decimal] = [:]
        for occurrence in occurrences(after: first, through: last) {
            byDay[calendar.startOfDay(for: occurrence.date), default: 0] += occurrence.amount
        }

        var running = balance(on: first)
        var points = [BalancePoint(date: first, balance: running)]
        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            running += byDay[day] ?? 0
            points.append(BalancePoint(date: day, balance: running))
        }
        return points
    }
}
