import Foundation
import Combine

class CurrencyService: ObservableObject {
    static let shared = CurrencyService()

    @Published var exchangeRates: [String: [String: Double]] = [:]
    @Published var lastUpdateDate: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOfflineMode = false

    private let apiBaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
    private let cacheKey = "CurrencyService.ExchangeRates"
    private let lastUpdateKey = "CurrencyService.LastUpdate"
    private let cacheExpiryHours: TimeInterval = 1
    private let networkTimeoutSeconds: TimeInterval = 10
    private var cancellables = Set<AnyCancellable>()
    private var lastConnectivityCheck: Date?
    private let connectivityCheckInterval: TimeInterval = 10 // 10 seconds minimum between checks

    private init() {
        loadCachedRates()
        if shouldUpdateRates() {
            fetchLatestRates()
        }
        // Start with offline mode detection based on cache age
        updateOfflineModeBasedOnCacheAge()
    }

    private func updateOfflineModeBasedOnCacheAge() {
        guard let lastUpdate = lastUpdateDate else {
            isOfflineMode = true
            return
        }

        let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
        // If data is more than 24 hours old, assume we might be offline until proven otherwise
        if hoursSinceUpdate > 24 {
            isOfflineMode = true
        }
    }
    
    func fetchLatestRates() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        let currencies = Currency.allCases
        let baseCurrency = "USD"
        var fetchedRates: [String: Double] = [:]
        let group = DispatchGroup()

        for currency in currencies {
            if currency.rawValue == baseCurrency {
                fetchedRates[currency.rawValue] = 1.0
                continue
            }

            group.enter()
            let symbol = "\(baseCurrency)\(currency.rawValue)=X"
            guard let url = URL(string: "\(apiBaseURL)/\(symbol)") else {
                group.leave()
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = networkTimeoutSeconds

            URLSession.shared.dataTaskPublisher(for: request)
                .map(\.data)
                .decode(type: YahooFinanceResponse.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            // Handle network errors silently
                        }
                        group.leave()
                    },
                    receiveValue: { [weak self] response in
                        if let rate = response.chart.result.first?.meta.regularMarketPrice, rate > 0 {
                            fetchedRates[currency.rawValue] = rate
                            self?.isOfflineMode = false
                        }
                    }
                )
                .store(in: &cancellables)
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false

            // Validate that we have sufficient data - we need more than just USD=1.0
            let validRates = fetchedRates.filter { $0.key != "USD" && $0.value > 0 }
            let hasValidData = validRates.count >= 2 // Need at least 2 non-USD rates

            if fetchedRates.isEmpty || !hasValidData {
                self?.isOfflineMode = true
                if self?.exchangeRates.isEmpty == true {
                    self?.loadDefaultRates()
                    self?.errorMessage = "Network unavailable. Using default exchange rates."
                } else {
                    self?.errorMessage = "Network returned incomplete data. Using cached exchange rates from \(self?.getRateAge() ?? "earlier")."
                }
            } else {
                self?.isOfflineMode = false
                self?.processYahooFinanceRates(fetchedRates, baseCurrency: baseCurrency)
            }
        }
    }

    private func processYahooFinanceRates(_ baseRates: [String: Double], baseCurrency: String) {
        var newRates: [String: [String: Double]] = [:]

        for fromCurrency in Currency.allCases {
            var currencyRates: [String: Double] = [:]

            for toCurrency in Currency.allCases {
                if fromCurrency == toCurrency {
                    currencyRates[toCurrency.rawValue] = 1.0
                } else if fromCurrency.rawValue == baseCurrency {
                    currencyRates[toCurrency.rawValue] = baseRates[toCurrency.rawValue] ?? 1.0
                } else if toCurrency.rawValue == baseCurrency {
                    if let fromRate = baseRates[fromCurrency.rawValue] {
                        currencyRates[toCurrency.rawValue] = 1.0 / fromRate
                    }
                } else {
                    if let fromRate = baseRates[fromCurrency.rawValue],
                       let toRate = baseRates[toCurrency.rawValue] {
                        currencyRates[toCurrency.rawValue] = toRate / fromRate
                    }
                }
            }

            newRates[fromCurrency.rawValue] = currencyRates
        }

        exchangeRates = newRates
        lastUpdateDate = Date()
        cacheRates()
        errorMessage = nil
    }

    private func loadCachedRates() {
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cachedRates = try? JSONDecoder().decode([String: [String: Double]].self, from: cachedData) {
            exchangeRates = cachedRates
        } else {
            loadDefaultRates()
        }

        if let cachedDate = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date {
            lastUpdateDate = cachedDate
        }
    }

    private func cacheRates() {
        if let encodedData = try? JSONEncoder().encode(exchangeRates) {
            UserDefaults.standard.set(encodedData, forKey: cacheKey)
        }
        UserDefaults.standard.set(lastUpdateDate, forKey: lastUpdateKey)
    }

    private func shouldUpdateRates() -> Bool {
        guard let lastUpdate = lastUpdateDate else { return true }
        let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
        return hoursSinceUpdate >= cacheExpiryHours
    }

    private func handleNetworkError(_ error: Error) {
        isOfflineMode = true

        if exchangeRates.isEmpty {
            loadDefaultRates()
            errorMessage = "Network unavailable. Using default exchange rates."
        } else {
            errorMessage = "Network unavailable. Using cached exchange rates from \(getRateAge() ?? "earlier")."
        }
    }

    private func handleFetchError(_ message: String) {
        errorMessage = message
        if exchangeRates.isEmpty {
            loadDefaultRates()
        }
    }

    private func loadDefaultRates() {
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

    func formatAmountWithFullCurrency(_ amount: Double, in currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        if let formattedNumber = formatter.string(from: NSNumber(value: amount)) {
            return "\(currency.code) \(currency.symbol)\(formattedNumber)"
        }

        return "\(currency.code) \(currency.symbol)\(String(format: "%.2f", amount))"
    }
    
    func getExchangeRate(from: Currency, to: Currency) -> Double {
        guard from != to else { return 1.0 }

        if let rates = exchangeRates[from.rawValue],
           let rate = rates[to.rawValue] {
            return rate
        }

        return 1.0
    }

    func refreshRates() {
        fetchLatestRates()
    }

    // Lightweight connectivity check - just tries to fetch one small currency rate
    func checkConnectivityAsync() {
        guard !isLoading else { return }

        // Throttle connectivity checks
        if let lastCheck = lastConnectivityCheck,
           Date().timeIntervalSince(lastCheck) < connectivityCheckInterval {
            return
        }

        lastConnectivityCheck = Date()
        let symbol = "USDCNY=X" // Use one common currency pair
        guard let url = URL(string: "\(apiBaseURL)/\(symbol)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Quick timeout for connectivity check

        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: YahooFinanceResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        let wasOffline = self?.isOfflineMode ?? false
                        self?.isOfflineMode = true
                        if !wasOffline {
                            NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil)
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    let wasOffline = self?.isOfflineMode ?? true
                    if response.chart.result.first?.meta.regularMarketPrice != nil {
                        self?.isOfflineMode = false
                        if wasOffline {
                            NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil)
                        }
                    } else {
                        self?.isOfflineMode = true
                        if !wasOffline {
                            NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    func refreshExchangeRates() async {
        await withUnsafeContinuation { continuation in
            fetchLatestRates()
            // Wait a bit for the network request to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                continuation.resume()
            }
        }
    }

    func getRateAge() -> String? {
        guard let lastUpdate = lastUpdateDate else { return nil }

        let timeInterval = Date().timeIntervalSince(lastUpdate)
        let hours = Int(timeInterval / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        } else {
            return "\(minutes)m ago"
        }
    }
}

struct YahooFinanceResponse: Codable {
    let chart: ChartData
}

struct ChartData: Codable {
    let result: [ResultData]
}

struct ResultData: Codable {
    let meta: MetaData
}

struct MetaData: Codable {
    let regularMarketPrice: Double
    let symbol: String
}
