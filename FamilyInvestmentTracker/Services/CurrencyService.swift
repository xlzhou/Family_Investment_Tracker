import Foundation

class CurrencyService: ObservableObject {
    static let shared = CurrencyService()
    
    @Published var exchangeRates: [String: [String: Double]] = [:]
    @Published var lastUpdateDate: Date?
    
    private init() {
        loadDefaultRates()
    }
    
    private func loadDefaultRates() {
        // Default exchange rates (these would normally come from an API)
        // Base currency rates relative to USD
        exchangeRates = [
            "USD": [
                "USD": 1.0,
                "CNY": 7.25,
                "TWD": 31.5,
                "HKD": 7.8,
                "JPY": 150.0,
                "EUR": 0.85
            ],
            "CNY": [
                "USD": 0.138,
                "CNY": 1.0,
                "TWD": 4.34,
                "HKD": 1.08,
                "JPY": 20.69,
                "EUR": 0.117
            ],
            "TWD": [
                "USD": 0.032,
                "CNY": 0.23,
                "TWD": 1.0,
                "HKD": 0.25,
                "JPY": 4.76,
                "EUR": 0.027
            ],
            "HKD": [
                "USD": 0.128,
                "CNY": 0.93,
                "TWD": 4.04,
                "HKD": 1.0,
                "JPY": 19.23,
                "EUR": 0.109
            ],
            "JPY": [
                "USD": 0.0067,
                "CNY": 0.048,
                "TWD": 0.21,
                "HKD": 0.052,
                "JPY": 1.0,
                "EUR": 0.0057
            ],
            "EUR": [
                "USD": 1.18,
                "CNY": 8.53,
                "TWD": 37.06,
                "HKD": 9.20,
                "JPY": 176.47,
                "EUR": 1.0
            ]
        ]
        lastUpdateDate = Date()
    }
    
    func convertAmount(_ amount: Double, from fromCurrency: Currency, to toCurrency: Currency) -> Double {
        guard fromCurrency != toCurrency else { return amount }
        
        if let rates = exchangeRates[fromCurrency.rawValue],
           let rate = rates[toCurrency.rawValue] {
            return amount * rate
        }
        
        // Fallback: convert through USD
        if let usdRate = exchangeRates[fromCurrency.rawValue]?["USD"],
           let targetRate = exchangeRates["USD"]?[toCurrency.rawValue] {
            return amount * usdRate * targetRate
        }
        
        return amount // Return original amount if conversion fails
    }
    
    func formatAmount(_ amount: Double, in currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        if let formattedNumber = formatter.string(from: NSNumber(value: amount)) {
            return "\(currency.symbol)\(formattedNumber)"
        }
        
        return "\(currency.symbol)\(String(format: "%.2f", amount))"
    }
    
    func getExchangeRate(from: Currency, to: Currency) -> Double {
        guard from != to else { return 1.0 }
        
        if let rates = exchangeRates[from.rawValue],
           let rate = rates[to.rawValue] {
            return rate
        }
        
        return 1.0
    }
}
