import Foundation
import CoreData

class MarketDataService: ObservableObject {
    static let shared = MarketDataService()

    @Published var isOfflineMode = false
    @Published var lastPricesUpdate: Date?
    @Published var errorMessage: String?

    private let session = URLSession.shared
    private let apiKey = "demo" // Using Yahoo Finance which doesn't require API key for basic quotes
    private let currencyService = CurrencyService.shared
    private let pricesCacheKey = "MarketDataService.CachedPrices"
    private let pricesUpdateKey = "MarketDataService.LastPricesUpdate"
    private let cacheExpiryMinutes: TimeInterval = 15
    private let networkTimeoutSeconds: TimeInterval = 10
    private var lastConnectivityCheck: Date?
    private let connectivityCheckInterval: TimeInterval = 10 // 10 seconds minimum between checks

    private init() {
        loadLastUpdateTime()
        // Start with offline mode detection based on cache age
        updateOfflineModeBasedOnCacheAge()
    }

    private func updateOfflineModeBasedOnCacheAge() {
        guard let lastUpdate = lastPricesUpdate else {
            isOfflineMode = true
            return
        }

        let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
        // If price data is more than 24 hours old, assume we might be offline until proven otherwise
        if hoursSinceUpdate > 24 {
            isOfflineMode = true
        }
    }
    
    // Yahoo Finance API endpoint
    private func yahooFinanceURL(for symbols: [String]) -> URL? {
        let symbolsString = symbols.joined(separator: ",")
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbolsString)"
        return URL(string: urlString)
    }
    
    func updateMarketPrices(for assets: [Asset], in context: NSManagedObjectContext) async {
        let symbols = assets.compactMap { $0.symbol?.uppercased() }.filter { !$0.isEmpty }
        let assetData = assets.compactMap { asset -> (objectID: NSManagedObjectID, symbol: String)? in
            guard let symbol = asset.symbol, !symbol.isEmpty else { return nil }
            return (objectID: asset.objectID, symbol: symbol.uppercased())
        }

        guard !symbols.isEmpty else { return }

        do {
            let (prices, successfulSymbols) = try await fetchPricesWithSuccess(for: symbols)

            await MainActor.run {
                var hasUpdates = false
                for data in assetData {
                    if let asset = try? context.existingObject(with: data.objectID) as? Asset,
                       let price = prices[data.symbol],
                       successfulSymbols.contains(data.symbol) {
                        asset.currentPrice = convertPrice(price, for: asset)
                        asset.lastPriceUpdate = Date()
                        hasUpdates = true
                    }
                }

                if hasUpdates {
                    lastPricesUpdate = Date()
                    cachePrices(prices)
                }

                do {
                    try context.save()
                } catch {
                    print("Error saving updated prices: \(error)")
                }
            }
        } catch {
            print("Error fetching market data: \(error)")
            await handleNetworkError()
        }
    }
    
    private func fetchPricesWithSuccess(for symbols: [String]) async throws -> ([String: Double], Set<String>) {
        guard !symbols.isEmpty else { return ([:], Set()) }

        // Try to fetch current prices from Yahoo Finance
        do {
            let (realPrices, successfulSymbols) = try await fetchRealPricesWithSuccess(for: symbols)
            var prices = realPrices

            if !realPrices.isEmpty {
                await MainActor.run {
                    self.isOfflineMode = false
                    self.errorMessage = nil
                }
            } else {
                // If we got no real prices, we might be offline
                await MainActor.run {
                    self.isOfflineMode = true
                }
            }

            // For symbols we couldn't fetch, try cached data (but don't mark as successful)
            let cachedPrices = loadCachedPrices()
            for symbol in symbols where prices[symbol.uppercased()] == nil {
                let upperSymbol = symbol.uppercased()
                if let cachedPrice = cachedPrices[upperSymbol] {
                    prices[upperSymbol] = cachedPrice
                }
                // Don't add simulated prices for failed fetches
            }

            return (prices, successfulSymbols)

        } catch {
            // Network error - use cached data if available but mark as failed
            let cachedPrices = loadCachedPrices()

            if !cachedPrices.isEmpty {
                var validPrices: [String: Double] = [:]
                for symbol in symbols {
                    let upperSymbol = symbol.uppercased()
                    if let cachedPrice = cachedPrices[upperSymbol] {
                        validPrices[upperSymbol] = cachedPrice
                    }
                }

                await MainActor.run {
                    self.isOfflineMode = true
                    let cacheAge = self.getPricesAge() ?? "unknown time"
                    self.errorMessage = "Network unavailable. Using cached price data from \(cacheAge)."
                }
                return (validPrices, Set()) // No successful fetches
            } else {
                await MainActor.run {
                    self.isOfflineMode = true
                    self.errorMessage = "Network unavailable and no cached price data available."
                }
            }

            throw error
        }
    }

    private func fetchPrices(for symbols: [String]) async throws -> [String: Double] {
        guard !symbols.isEmpty else { return [:] }

        // Try to fetch current prices from Yahoo Finance
        do {
            let realPrices = try await fetchRealPrices(for: symbols)
            var prices = realPrices

            if !realPrices.isEmpty {
                await MainActor.run {
                    self.isOfflineMode = false
                    self.errorMessage = nil
                }
            } else {
                // If we got no real prices, we might be offline
                await MainActor.run {
                    self.isOfflineMode = true
                }
            }

            // For symbols we couldn't fetch, try cached data first (regardless of age), then fallback to simulation
            let cachedPrices = loadCachedPrices()
            for symbol in symbols where prices[symbol.uppercased()] == nil {
                let upperSymbol = symbol.uppercased()
                if let cachedPrice = cachedPrices[upperSymbol] {
                    prices[upperSymbol] = cachedPrice
                } else {
                    prices[upperSymbol] = generateSimulatedPrice(for: symbol)
                }
            }

            return prices

        } catch {
            // Network error - use cached data if available (regardless of age)
            let cachedPrices = loadCachedPrices()

            if !cachedPrices.isEmpty {
                var validPrices: [String: Double] = [:]
                for symbol in symbols {
                    let upperSymbol = symbol.uppercased()
                    if let cachedPrice = cachedPrices[upperSymbol] {
                        validPrices[upperSymbol] = cachedPrice
                    } else {
                        validPrices[upperSymbol] = generateSimulatedPrice(for: symbol)
                    }
                }

                await MainActor.run {
                    self.isOfflineMode = true
                    let cacheAge = self.getPricesAge() ?? "unknown time"
                    self.errorMessage = "Network unavailable. Using cached price data from \(cacheAge)."
                }
                return validPrices
            } else {
                await MainActor.run {
                    self.isOfflineMode = true
                    self.errorMessage = "Network unavailable and no cached price data available."
                }
            }

            throw error
        }
    }
    
    private func generateSimulatedPrice(for symbol: String) -> Double {
        // Generate realistic stock prices based on symbol
        let basePrice: Double
        
        switch symbol.uppercased() {
        case "AAPL":
            basePrice = 175.0
        case "GOOGL", "GOOG":
            basePrice = 2800.0
        case "MSFT":
            basePrice = 380.0
        case "AMZN":
            basePrice = 3200.0
        case "TSLA":
            basePrice = 240.0
        case "NVDA":
            basePrice = 450.0
        case "META":
            basePrice = 320.0
        case "NFLX":
            basePrice = 425.0
        case "SPY":
            basePrice = 450.0
        case "QQQ":
            basePrice = 380.0
        case "VTI":
            basePrice = 240.0
        case "BTC-USD":
            basePrice = 43000.0
        case "ETH-USD":
            basePrice = 2500.0
        default:
            basePrice = Double.random(in: 10...500)
        }
        
        // Add some random variation (±5%)
        let variation = Double.random(in: -0.05...0.05)
        return basePrice * (1 + variation)
    }
}

private extension MarketDataService {
    func convertPrice(_ price: Double, for asset: Asset) -> Double {
        guard let holdings = asset.holdings?.allObjects as? [Holding], !holdings.isEmpty else {
            return price
        }

        let portfolios = Set(holdings.compactMap { $0.portfolio })
        guard portfolios.count == 1, let portfolio = portfolios.first else {
            return price
        }

        let targetCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
        return currencyService.convertAmount(price, from: .usd, to: targetCurrency)
    }
}

// Alternative implementation using Yahoo Finance API (for production use)
extension MarketDataService {
    private func fetchRealPrices(for symbols: [String]) async throws -> [String: Double] {
        let uniqueSymbols = Array(Set(symbols.map { $0.uppercased() }))
        guard !uniqueSymbols.isEmpty else { return [:] }

        var prices: [String: Double] = [:]

        let session = session
        let service = self
        try await withThrowingTaskGroup(of: (String, Double?).self) { group in
            for symbol in uniqueSymbols {
                group.addTask {
                    guard let url = service.yahooFinanceURL(for: [symbol]) else {
                        return (symbol, nil)
                    }
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = service.networkTimeoutSeconds

                        let (data, response) = try await session.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              200..<300 ~= httpResponse.statusCode else {
                            return (symbol, nil)
                        }
                        let quote = service.parseYahooFinanceResponse(data)
                        return (symbol, quote)
                    } catch {
                        return (symbol, nil)
                    }
                }
            }

            for try await (symbol, price) in group {
                if let price = price, price > 0 {
                    prices[symbol] = price
                }
            }
        }

        return prices
    }

    private func fetchRealPricesWithSuccess(for symbols: [String]) async throws -> ([String: Double], Set<String>) {
        let uniqueSymbols = Array(Set(symbols.map { $0.uppercased() }))
        guard !uniqueSymbols.isEmpty else { return ([:], Set()) }

        var prices: [String: Double] = [:]
        var successfulSymbols: Set<String> = Set()

        let session = session
        let service = self
        try await withThrowingTaskGroup(of: (String, Double?).self) { group in
            for symbol in uniqueSymbols {
                group.addTask {
                    guard let url = service.yahooFinanceURL(for: [symbol]) else {
                        return (symbol, nil)
                    }
                    do {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = service.networkTimeoutSeconds

                        let (data, response) = try await session.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              200..<300 ~= httpResponse.statusCode else {
                            return (symbol, nil)
                        }
                        let quote = service.parseYahooFinanceResponse(data)
                        return (symbol, quote)
                    } catch {
                        return (symbol, nil)
                    }
                }
            }

            for try await (symbol, price) in group {
                if let price = price, price > 0 {
                    prices[symbol] = price
                    successfulSymbols.insert(symbol)
                }
            }
        }

        return (prices, successfulSymbols)
    }

    private func parseYahooFinanceResponse(_ data: Data) -> Double? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = json["chart"] as? [String: Any],
               let result = chart["result"] as? [[String: Any]],
               let firstResult = result.first,
               let meta = firstResult["meta"] as? [String: Any],
               let regularMarketPrice = meta["regularMarketPrice"] as? Double {
                return regularMarketPrice
            }
        } catch {
            print("Error parsing Yahoo Finance response: \(error)")
        }
        return nil
    }
}

// Caching functionality
extension MarketDataService {
    private func cachePrices(_ prices: [String: Double]) {
        if let encodedData = try? JSONEncoder().encode(prices) {
            UserDefaults.standard.set(encodedData, forKey: pricesCacheKey)
        }
        UserDefaults.standard.set(Date(), forKey: pricesUpdateKey)
    }

    private func loadCachedPrices() -> [String: Double] {
        guard let cachedData = UserDefaults.standard.data(forKey: pricesCacheKey),
              let cachedPrices = try? JSONDecoder().decode([String: Double].self, from: cachedData) else {
            return [:]
        }
        return cachedPrices
    }

    private func loadLastUpdateTime() {
        if let cachedDate = UserDefaults.standard.object(forKey: pricesUpdateKey) as? Date {
            lastPricesUpdate = cachedDate
        }
    }

    private func shouldUseCachedPrice() -> Bool {
        guard let lastUpdate = lastPricesUpdate else { return false }
        let minutesSinceUpdate = Date().timeIntervalSince(lastUpdate) / 60
        return minutesSinceUpdate <= cacheExpiryMinutes
    }

    @MainActor
    private func handleNetworkError() {
        isOfflineMode = true
        let cachedPrices = loadCachedPrices()

        if cachedPrices.isEmpty {
            errorMessage = "Network unavailable and no cached price data available."
        } else if shouldUseCachedPrice() {
            errorMessage = "Network unavailable. Using recent cached price data."
        } else {
            errorMessage = "Network unavailable. Cached price data may be outdated."
        }
    }

    func getPricesAge() -> String? {
        guard let lastUpdate = lastPricesUpdate else { return nil }

        let timeInterval = Date().timeIntervalSince(lastUpdate)
        let hours = Int(timeInterval / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        } else {
            return "\(minutes)m ago"
        }
    }

    // Lightweight connectivity check - just tries to fetch one stock price
    func checkConnectivityAsync() {
        // Throttle connectivity checks
        if let lastCheck = lastConnectivityCheck,
           Date().timeIntervalSince(lastCheck) < connectivityCheckInterval {
            return
        }

        lastConnectivityCheck = Date()

        let testSymbol = "AAPL" // Use a common stock for testing
        guard let url = yahooFinanceURL(for: [testSymbol]) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Quick timeout for connectivity check

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                let wasOffline = self?.isOfflineMode ?? true
                if error != nil {
                    self?.isOfflineMode = true
                    if !wasOffline {
                        NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil)
                    }
                } else if let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          let data = data,
                          let quote = self?.parseYahooFinanceResponse(data),
                          quote > 0 {
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
        }.resume()
    }
}

// Background task for periodic price updates
extension MarketDataService {
    func startPeriodicUpdates(for assets: [Asset], in context: NSManagedObjectContext) {
        Task {
            while true {
                await updateMarketPrices(for: assets, in: context)

                // Update every 5 minutes during market hours
                try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
            }
        }
    }
}
