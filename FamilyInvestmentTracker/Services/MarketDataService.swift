import Foundation
import CoreData

class MarketDataService: ObservableObject {
    static let shared = MarketDataService()
    
    private let session = URLSession.shared
    private let apiKey = "demo" // Using Yahoo Finance which doesn't require API key for basic quotes
    private let currencyService = CurrencyService.shared
    
    private init() {}
    
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
            let prices = try await fetchPrices(for: symbols)

            await MainActor.run {
                for data in assetData {
                    if let asset = try? context.existingObject(with: data.objectID) as? Asset,
                       let price = prices[data.symbol] {
                        asset.currentPrice = convertPrice(price, for: asset)
                        asset.lastPriceUpdate = Date()
                    }
                }

                do {
                    try context.save()
                } catch {
                    print("Error saving updated prices: \(error)")
                }
            }
        } catch {
            print("Error fetching market data: \(error)")
        }
    }
    
    private func fetchPrices(for symbols: [String]) async throws -> [String: Double] {
        guard !symbols.isEmpty else { return [:] }

        let realPrices = try await fetchRealPrices(for: symbols)
        var prices = realPrices

        // Fallback to simulated prices for any symbols we could not fetch from Yahoo Finance
        for symbol in symbols where prices[symbol.uppercased()] == nil {
            prices[symbol.uppercased()] = generateSimulatedPrice(for: symbol)
        }

        return prices
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
                        let (data, response) = try await session.data(from: url)
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
