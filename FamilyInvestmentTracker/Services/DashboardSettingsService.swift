import Foundation

final class DashboardSettingsService: ObservableObject {
    static let shared = DashboardSettingsService()

    @Published private(set) var dashboardCurrency: Currency
    @Published var includeInsuranceInPerformance: Bool {
        didSet {
            UserDefaults.standard.set(includeInsuranceInPerformance, forKey: includeInsuranceKey)
        }
    }

    private let storageKey = "DashboardCurrencyCode"
    private let includeInsuranceKey = "IncludeInsuranceInPerformance"
    private var hasStoredValue = false

    private init() {
        if let storedCode = UserDefaults.standard.string(forKey: storageKey),
           let storedCurrency = Currency(rawValue: storedCode) {
            dashboardCurrency = storedCurrency
            hasStoredValue = true
        } else {
            dashboardCurrency = .usd
        }

        if UserDefaults.standard.object(forKey: includeInsuranceKey) != nil {
            includeInsuranceInPerformance = UserDefaults.standard.bool(forKey: includeInsuranceKey)
        } else {
            includeInsuranceInPerformance = true
            UserDefaults.standard.set(true, forKey: includeInsuranceKey)
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
