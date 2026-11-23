import SwiftUI

/// Solde de départ et date à laquelle il a été constaté, stockés dans les préférences.
/// S'utilise comme propriété d'une vue : `private var account = AccountSettings()`.
struct AccountSettings: DynamicProperty {
    @AppStorage("startingBalance") private var balanceRaw: String = "0"
    @AppStorage("referenceDate") private var dateRaw: Double = 0
    @AppStorage("trackingStart") private var trackingRaw: Double = 0

    /// Début du suivi : les échéances postérieures restent « à venir » tant qu'elles ne sont pas cochées,
    /// même si le solde est corrigé à la main ensuite.
    var trackingStart: Date {
        get { trackingRaw == 0 ? referenceDate : Date(timeIntervalSinceReferenceDate: trackingRaw) }
        nonmutating set { trackingRaw = newValue.timeIntervalSinceReferenceDate }
    }

    var isConfigured: Bool { dateRaw != 0 }

    var startingBalance: Decimal {
        get { Decimal(string: balanceRaw) ?? 0 }
        nonmutating set { balanceRaw = newValue.description }
    }

    var referenceDate: Date {
        get { dateRaw == 0 ? Calendar.current.startOfDay(for: .now) : Date(timeIntervalSinceReferenceDate: dateRaw) }
        nonmutating set { dateRaw = newValue.timeIntervalSinceReferenceDate }
    }
}

enum Money {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    static func format(_ value: Decimal, signed: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode)
        return signed ? value.formatted(style.sign(strategy: .always())) : value.formatted(style)
    }

    /// Accepte « 1 234,56 », « 1,234.56 », « -12.5 », « 45 € »…
    /// Le dernier séparateur (virgule ou point) est le séparateur décimal.
    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.filter { "0123456789,.-".contains($0) }
        let negative = cleaned.hasPrefix("-")
        cleaned.removeAll { $0 == "-" }
        if let last = cleaned.lastIndex(where: { $0 == "," || $0 == "." }) {
            let integerPart = cleaned[..<last].filter(\.isNumber)
            let fraction = cleaned[cleaned.index(after: last)...]
            cleaned = integerPart + "." + fraction
        }
        guard cleaned.contains(where: \.isNumber), let value = Decimal(string: cleaned) else { return nil }
        return negative ? -value : value
    }

    /// Texte éditable avec le séparateur décimal local.
    static func editableText(_ value: Decimal) -> String {
        let separator = Locale.current.decimalSeparator ?? ","
        return value.description.replacingOccurrences(of: ".", with: separator)
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
