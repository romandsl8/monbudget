import XCTest
import SwiftData
@testable import MonBudget

final class MoneyTests: XCTestCase {
    func testParseFrenchAndAmericanFormats() {
        XCTAssertEqual(Money.parse("1 234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Money.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Money.parse("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(Money.parse("-80"), -80)
        XCTAssertEqual(Money.parse("1\u{202F}200,00 €"), 1200)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
    }
}

@MainActor
final class BalanceTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar: Calendar!

    override func setUp() async throws {
        container = try ModelContainer(
            for: BudgetEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func insert(_ entry: BudgetEntry) -> BudgetEntry {
        container.mainContext.insert(entry)
        return entry
    }

    func testMonthlyOn31stDoesNotDrift() {
        let entry = insert(BudgetEntry(name: "Loyer", amount: 700, kind: .expense,
                                       frequency: .monthly, startDate: date(2027, 1, 31)))
        let dates = entry.occurrenceDates(after: date(2027, 1, 1), through: date(2027, 5, 31), calendar: calendar)
        let days = dates.map { calendar.component(.day, from: $0) }
        XCTAssertEqual(days, [31, 28, 31, 30, 31])
    }

    func testEndDateAndPause() {
        let entry = insert(BudgetEntry(name: "Crédit", amount: 100, kind: .expense, frequency: .monthly,
                                       startDate: date(2027, 1, 5), endDate: date(2027, 3, 5)))
        XCTAssertEqual(entry.occurrenceDates(after: date(2026, 12, 31), through: date(2027, 12, 31), calendar: calendar).count, 3)
        entry.isActive = false
        XCTAssertTrue(entry.occurrenceDates(after: date(2026, 12, 31), through: date(2027, 12, 31), calendar: calendar).isEmpty)
    }

    func testBalanceExcludesReferenceDayAndIncludesTarget() {
        let salary = insert(BudgetEntry(name: "Salaire", amount: 2000, kind: .income,
                                        frequency: .monthly, startDate: date(2027, 1, 28)))
        let rent = insert(BudgetEntry(name: "Loyer", amount: 700, kind: .expense,
                                      frequency: .monthly, startDate: date(2027, 1, 5)))
        let engine = BalanceEngine(startingBalance: 1000, referenceDate: date(2027, 2, 5),
                                   entries: [salary, rent], calendar: calendar)

        // Le loyer du 5 février est déjà inclus dans le solde de départ.
        XCTAssertEqual(engine.balance(on: date(2027, 2, 5)), 1000)
        XCTAssertEqual(engine.balance(on: date(2027, 2, 27)), 1000)
        XCTAssertEqual(engine.balance(on: date(2027, 2, 28)), 3000)
        XCTAssertEqual(engine.balance(on: date(2027, 3, 5)), 2300)
        // Dans le passé : on retire ce qui s'est passé depuis.
        XCTAssertEqual(engine.balance(on: date(2027, 1, 27)), 1000 - 2000 + 700)
    }

    func testProjectionMatchesBalance() {
        let phone = insert(BudgetEntry(name: "Téléphone", amount: 20, kind: .expense,
                                       frequency: .weekly, startDate: date(2027, 1, 1)))
        let engine = BalanceEngine(startingBalance: 500, referenceDate: date(2027, 1, 1),
                                   entries: [phone], calendar: calendar)
        let points = engine.projection(from: date(2027, 1, 1), days: 30)
        XCTAssertEqual(points.count, 31)
        for point in points {
            XCTAssertEqual(point.balance, engine.balance(on: point.date))
        }
        XCTAssertEqual(points.last?.balance, 500 - 4 * 20)
    }

    func testMonthSummaryRemainingBudget() {
        let salary = insert(BudgetEntry(name: "Salaire", amount: 2500, kind: .income,
                                        frequency: .monthly, startDate: date(2027, 1, 28)))
        let rent = insert(BudgetEntry(name: "Loyer", amount: 800, kind: .expense, frequency: .monthly,
                                      startDate: date(2027, 1, 5), category: "Logement"))
        let edf = insert(BudgetEntry(name: "EDF", amount: 90, kind: .expense, frequency: .monthly,
                                     startDate: date(2027, 1, 12), category: "Énergie"))
        let insurance = insert(BudgetEntry(name: "Assurance", amount: 300, kind: .expense,
                                           frequency: .yearly, startDate: date(2027, 3, 15), category: "Logement"))
        // Le solde de départ et sa date n'influencent pas le budget du mois.
        let engine = BalanceEngine(startingBalance: 42, referenceDate: date(2027, 3, 20),
                                   entries: [salary, rent, edf, insurance], calendar: calendar)

        let march = engine.monthSummary(containing: date(2027, 3, 17))
        XCTAssertEqual(march.month, date(2027, 3, 1))
        XCTAssertEqual(march.daysInMonth, 31)
        XCTAssertEqual(march.income, 2500)
        XCTAssertEqual(march.expenses, 1190)
        XCTAssertEqual(march.remaining, 1310)
        XCTAssertEqual(march.expensesByCategory.first?.category, "Logement")
        XCTAssertEqual(march.expensesByCategory.first?.total, 1100)

        let april = engine.monthSummary(containing: date(2027, 4, 2))
        XCTAssertEqual(april.remaining, 2500 - 890)
        XCTAssertEqual(april.daysInMonth, 30)

        XCTAssertEqual(engine.monthSummaries(around: date(2027, 3, 17), before: 2, after: 12).count, 15)
    }

    func testOnceEntry() {
        let gift = insert(BudgetEntry(name: "Cadeau", amount: 50, kind: .expense,
                                      frequency: .once, startDate: date(2027, 6, 10)))
        let engine = BalanceEngine(startingBalance: 0, referenceDate: date(2027, 6, 1),
                                   entries: [gift], calendar: calendar)
        XCTAssertEqual(engine.balance(on: date(2027, 6, 9)), 0)
        XCTAssertEqual(engine.balance(on: date(2027, 12, 31)), -50)
    }
}
