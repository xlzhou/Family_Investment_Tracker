import Foundation

enum Formatters {
    private static func makeNumberFormatter(style: NumberFormatter.Style = .decimal,
                                             fractionDigits: Int = 2,
                                             locale: Locale = .current) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = style
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f
    }

    static func decimal(_ value: Double, fractionDigits: Int = 2) -> String {
        let f = makeNumberFormatter(style: .decimal, fractionDigits: fractionDigits)
        return f.string(from: NSNumber(value: value)) ?? String(format: "%0.*f", fractionDigits, value)
    }

    static func currency(_ value: Double, symbol: String = "$", fractionDigits: Int = 2) -> String {
        let f = makeNumberFormatter(style: .decimal, fractionDigits: fractionDigits)
        let core = f.string(from: NSNumber(value: value)) ?? String(format: "%0.*f", fractionDigits, value)
        return "\(symbol)\(core)"
    }

    static func signedCurrency(_ value: Double, symbol: String = "$", fractionDigits: Int = 2, showPlus: Bool = true) -> String {
        let sign = value >= 0 ? (showPlus ? "+" : "") : "-"
        return sign + currency(abs(value), symbol: symbol, fractionDigits: fractionDigits)
    }

    static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        let f = makeNumberFormatter(style: .decimal, fractionDigits: fractionDigits)
        let core = f.string(from: NSNumber(value: value)) ?? String(format: "%0.*f", fractionDigits, value)
        let symbol = f.percentSymbol ?? "%"
        return core + symbol
    }

    static func signedPercent(_ value: Double, fractionDigits: Int = 1, showPlus: Bool = true) -> String {
        let sign = value >= 0 ? (showPlus ? "+" : "") : "-"
        return sign + percent(abs(value), fractionDigits: fractionDigits)
    }
}
