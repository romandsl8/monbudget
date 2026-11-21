import Foundation

/// État d'un crédit calculé à partir de la mensualité, de la première et de la dernière échéance.
struct LoanStatus {
    let monthlyAmount: Decimal
    let totalPayments: Int
    let remainingPayments: Int
    let nextDate: Date?
    let lastDate: Date?

    var paidPayments: Int { totalPayments - remainingPayments }
    var totalAmount: Decimal { monthlyAmount * Decimal(totalPayments) }
    /// Montant restant à rembourser = mensualité × échéances restantes.
    var remainingAmount: Decimal { monthlyAmount * Decimal(remainingPayments) }
    var paidAmount: Decimal { totalAmount - remainingAmount }

    var progress: Double {
        totalPayments > 0 ? Double(paidPayments) / Double(totalPayments) : 0
    }
    var isFinished: Bool { totalPayments > 0 && remainingPayments == 0 }
}

extension BudgetEntry {
    /// nil si le crédit n'a pas de date de fin.
    /// Les échéances passées sont considérées comme payées, sauf celle du jour si elle n'est pas pointée.
    func loanStatus(today: Date = .now, calendar: Calendar = .current) -> LoanStatus? {
        guard let endDate else { return nil }
        let start = calendar.startOfDay(for: startDate)
        guard let dayBeforeStart = calendar.date(byAdding: .day, value: -1, to: start) else { return nil }
        let all = scheduleDates(after: dayBeforeStart, through: endDate, calendar: calendar)

        let startOfToday = calendar.startOfDay(for: today)
        var remaining: [Date] = []
        for date in all {
            if date > startOfToday {
                remaining.append(date)
            } else if date == startOfToday && !isCleared(on: date, calendar: calendar) {
                remaining.append(date)
            }
        }

        return LoanStatus(
            monthlyAmount: amount,
            totalPayments: all.count,
            remainingPayments: remaining.count,
            nextDate: remaining.first,
            lastDate: all.last
        )
    }
}
