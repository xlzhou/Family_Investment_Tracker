import Foundation
import CoreData
import SwiftUI

class PortfolioViewModel: ObservableObject {
    @Published var isUpdatingPrices = false
    
    private let marketDataService = MarketDataService.shared
    
    func updatePortfolioPrices(portfolio: Portfolio, context: NSManagedObjectContext) {
        guard !isUpdatingPrices else { return }

        isUpdatingPrices = true
        let portfolioObjectID = portfolio.objectID

        Task { [weak self] in
            guard let self = self else { return }
            let assets = self.getAllAssetsInPortfolio(portfolio)
            await self.marketDataService.updateMarketPrices(for: assets, in: context)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if let portfolioInContext = try? context.existingObject(with: portfolioObjectID) as? Portfolio {
                    self.updatePortfolioTotalValue(portfolio: portfolioInContext, context: context)
                }
                self.isUpdatingPrices = false
            }
        }
    }
    
    private func getAllAssetsInPortfolio(_ portfolio: Portfolio) -> [Asset] {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        return holdings.compactMap { $0.asset }
    }
    
    private func updatePortfolioTotalValue(portfolio: Portfolio, context: NSManagedObjectContext) {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        
        let totalValue = holdings.reduce(0.0) { total, holding in
            guard let asset = holding.asset else { return total }
            return total + (holding.quantity * asset.currentPrice)
        }
        
        portfolio.totalValue = totalValue
        portfolio.updatedAt = Date()
        
        do {
            try context.save()
        } catch {
            print("Error updating portfolio total value: \(error)")
        }
    }
}

extension PortfolioViewModel {
    func calculatePortfolioPerformance(portfolio: Portfolio) -> PortfolioPerformance {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        
        var totalCurrentValue: Double = 0
        var totalCostBasis: Double = 0
        var totalDividends: Double = 0
        var totalRealizedGains: Double = 0
        
        for holding in holdings {
            guard let asset = holding.asset else { continue }
            
            totalCurrentValue += holding.quantity * asset.currentPrice
            totalCostBasis += holding.quantity * holding.averageCostBasis
            totalDividends += holding.totalDividends
            totalRealizedGains += holding.realizedGainLoss
        }
        
        let unrealizedGainLoss = totalCurrentValue - totalCostBasis
        let totalReturn = unrealizedGainLoss + totalRealizedGains + totalDividends
        let totalReturnPercentage = totalCostBasis > 0 ? (totalReturn / totalCostBasis) * 100 : 0
        
        return PortfolioPerformance(
            currentValue: totalCurrentValue,
            costBasis: totalCostBasis,
            unrealizedGainLoss: unrealizedGainLoss,
            realizedGainLoss: totalRealizedGains,
            totalDividends: totalDividends,
            totalReturn: totalReturn,
            totalReturnPercentage: totalReturnPercentage
        )
    }
    
    func getAssetAllocation(portfolio: Portfolio) -> [AssetAllocation] {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        
        var typeAllocations: [String: Double] = [:]
        var totalValue: Double = 0
        
        for holding in holdings {
            guard let asset = holding.asset,
                  let assetType = asset.assetType else { continue }
            
            let value = holding.quantity * asset.currentPrice
            typeAllocations[assetType, default: 0] += value
            totalValue += value
        }
        
        return typeAllocations.map { type, value in
            AssetAllocation(
                type: type,
                value: value,
                percentage: totalValue > 0 ? (value / totalValue) * 100 : 0
            )
        }.sorted { $0.value > $1.value }
    }
}

struct PortfolioPerformance {
    let currentValue: Double
    let costBasis: Double
    let unrealizedGainLoss: Double
    let realizedGainLoss: Double
    let totalDividends: Double
    let totalReturn: Double
    let totalReturnPercentage: Double
}

struct AssetAllocation {
    let type: String
    let value: Double
    let percentage: Double
}