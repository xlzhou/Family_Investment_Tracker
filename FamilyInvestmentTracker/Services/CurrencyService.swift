import Foundation
import Combine

class CurrencyService: ObservableObject {
    static let shared = CurrencyService()

    @Published var exchangeRates: [String: [String: Double]] = [:]
    @Published var lastUpdateDate: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiBaseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
    private let cacheKey = "CurrencyService.ExchangeRates"
    private let lastUpdateKey = "CurrencyService.LastUpdate"
    private let cacheExpiryHours: TimeInterval = 1
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadCachedRates()
        if shouldUpdateRates() {
            fetchLatestRates()
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

            URLSession.shared.dataTaskPublisher(for: url)
                .map(\.data)
                .decode(type: YahooFinanceResponse.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("Error fetching \(symbol): \(error)")
                        }
                        group.leave()
                    },
                    receiveValue: { response in
                        if let rate = response.chart.result.first?.meta.regularMarketPrice {
                            fetchedRates[currency.rawValue] = rate
                        }
                    }
                )
                .store(in: &cancellables)
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.processYahooFinanceRates(fetchedRates, baseCurrency: baseCurrency)
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
