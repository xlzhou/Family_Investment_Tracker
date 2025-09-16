import Foundation
import CoreData

class MarketDataService: ObservableObject {
    static let shared = MarketDataService()
    
    private let session = URLSession.shared
    private let apiKey = "demo" // Using Yahoo Finance which doesn't require API key for basic quotes
    
    private init() {}
    
    // Yahoo Finance API endpoint
    private func yahooFinanceURL(for symbols: [String]) -> URL? {
        let symbolsString = symbols.joined(separator: ",")
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbolsString)"
        return URL(string: urlString)
    }
    
    func updateMarketPrices(for assets: [Asset], in context: NSManagedObjectContext) async {
        let symbols = assets.compactMap { $0.symbol }.filter { !$0.isEmpty }
        
        guard !symbols.isEmpty else { return }
        
        do {
            let prices = try await fetchPrices(for: symbols)
            
            await MainActor.run {
                for asset in assets {
                    if let symbol = asset.symbol,
                       let price = prices[symbol] {
                        asset.currentPrice = price
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
        var prices: [String: Double] = [:]
        
        // For demo purposes, we'll use a simulated API response
        // In production, you would use Yahoo Finance API or Alpha Vantage
        for symbol in symbols {
            let simulatedPrice = generateSimulatedPrice(for: symbol)
            prices[symbol] = simulatedPrice
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
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

// Alternative implementation using Yahoo Finance API (for production use)
extension MarketDataService {
    private func fetchRealPrices(for symbols: [String]) async throws -> [String: Double] {
        var prices: [String: Double] = [:]
        
        for symbol in symbols {
            if let url = yahooFinanceURL(for: [symbol]) {
                let (data, _) = try await session.data(from: url)
                
                if let quote = parseYahooFinanceResponse(data) {
                    prices[symbol] = quote
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