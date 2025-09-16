import Foundation

enum Formatters {
    private static func makeNumberFormatter(style: NumberFormatter.Style = .decimal,
                                             fractionDigits: Int = 2,
                                             groupingSeparator: String = ",",
                                             decimalSeparator: String? = nil) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = style
        f.usesGroupingSeparator = true
        f.groupingSeparator = groupingSeparator
        if let decimalSeparator = decimalSeparator { f.decimalSeparator = decimalSeparator }
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
        return core + "%"
    }

    static func signedPercent(_ value: Double, fractionDigits: Int = 1, showPlus: Bool = true) -> String {
        let sign = value >= 0 ? (showPlus ? "+" : "") : "-"
        return sign + percent(abs(value), fractionDigits: fractionDigits)
    }
}

