import Foundation

final class DashboardSettingsService: ObservableObject {
    static let shared = DashboardSettingsService()

    @Published private(set) var dashboardCurrency: Currency

    private let storageKey = "DashboardCurrencyCode"
    private var hasStoredValue = false

    private init() {
        if let storedCode = UserDefaults.standard.string(forKey: storageKey),
           let storedCurrency = Currency(rawValue: storedCode) {
            dashboardCurrency = storedCurrency
            hasStoredValue = true
        } else {
            dashboardCurrency = .usd
        }
    }

    func updateCurrency(_ currency: Currency) {
        guard dashboardCurrency != currency else { return }
        dashboardCurrency = currency
        hasStoredValue = true
        UserDefaults.standard.set(currency.rawValue, forKey: storageKey)
    }

    func ensureCurrencyIfUnset(_ currency: Currency) {
        guard !hasStoredValue else { return }
        dashboardCurrency = currency
        hasStoredValue = true
        UserDefaults.standard.set(currency.rawValue, forKey: storageKey)
    }
}
