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
        var autoFetchAssets: [Asset] = []

        for holding in holdings {
            guard let asset = holding.asset else { continue }

            // Check if any transaction for this asset has auto-fetch enabled
            let transactions = asset.transactions?.allObjects as? [Transaction] ?? []
            let hasAutoFetchEnabled = transactions.contains { transaction in
                transaction.autoFetchPrice
            }

            if hasAutoFetchEnabled && !autoFetchAssets.contains(where: { $0.objectID == asset.objectID }) {
                autoFetchAssets.append(asset)
            }
        }

        return autoFetchAssets
    }
    
    private func updatePortfolioTotalValue(portfolio: Portfolio, context: NSManagedObjectContext) {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        
        let totalValue = holdings.reduce(0.0) { total, holding in
            guard let asset = holding.asset else { return total }
            // For insurance assets, use cash value; for others, use market value
            if asset.assetType == "Insurance" {
                return total + (holding.value(forKey: "cashValue") as? Double ?? 0)
            } else {
                return total + (holding.quantity * asset.currentPrice)
            }
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

            // For insurance assets, use cash value; for others, use market value
            if asset.assetType == "Insurance" {
                totalCurrentValue += (holding.value(forKey: "cashValue") as? Double ?? 0)
                // For insurance, cost basis is typically the premiums paid (stored as amount)
                // We'll use a simplified approach here
                totalCostBasis += 0 // Insurance premiums don't count as cost basis in traditional sense
            } else {
                totalCurrentValue += holding.quantity * asset.currentPrice
                totalCostBasis += holding.quantity * holding.averageCostBasis
            }

            totalDividends += holding.totalDividends
            totalRealizedGains += holding.realizedGainLoss
        }
        
        totalCurrentValue += portfolio.resolvedCashBalance()

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

            // For insurance assets, use cash value; for others, use market value
            let value: Double
            if assetType == "Insurance" {
                value = holding.value(forKey: "cashValue") as? Double ?? 0
            } else {
                value = holding.quantity * asset.currentPrice
            }

            typeAllocations[assetType, default: 0] += value
            totalValue += value
        }

        let cashBalance = portfolio.resolvedCashBalance()
        if cashBalance != 0 {
            typeAllocations["Cash", default: 0] += cashBalance
            totalValue += cashBalance
        }

        return typeAllocations.map { type, value in
            AssetAllocation(
                type: type,
                value: value,
                percentage: totalValue > 0 ? (value / totalValue) * 100 : 0
            )
        }.sorted { $0.value > $1.value }
    }

    func getInstitutionAllocations(portfolio: Portfolio) -> [InstitutionAllocation] {
        var institutionValues: [String: Double] = [:]

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let institutions = Set(transactions.compactMap { $0.institution })
        var allocatedInstitutionCash: Double = 0

        for institution in institutions {
            let name = normalizedInstitutionName(institution)
            let cash = institution.cashBalanceSafe
            if abs(cash) > 0.01 {
                institutionValues[name, default: 0] += cash
                allocatedInstitutionCash += cash
            }
        }

        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        for holding in holdings {
            guard let asset = holding.asset else { continue }

            let value: Double
            if asset.assetType == AssetType.insurance.rawValue {
                value = holding.value(forKey: "cashValue") as? Double ?? 0
            } else {
                value = holding.quantity * asset.currentPrice
            }

            guard abs(value) > 0 else { continue }

            if let availabilitySet = asset.value(forKey: "institutionAvailabilities") as? Set<NSManagedObject>, !availabilitySet.isEmpty {
                let relatedInstitutions = availabilitySet.compactMap { $0.value(forKey: "institution") as? Institution }
                if !relatedInstitutions.isEmpty {
                    let allocationShare = value / Double(relatedInstitutions.count)
                    for institution in relatedInstitutions {
                        let name = normalizedInstitutionName(institution)
                        institutionValues[name, default: 0] += allocationShare
                    }
                    continue
                }
            }

            if let fallbackInstitution = latestInstitution(for: asset, in: portfolio) {
                let name = normalizedInstitutionName(fallbackInstitution)
                institutionValues[name, default: 0] += value
            } else {
                institutionValues["Unassigned", default: 0] += value
            }
        }

        let resolvedCash = portfolio.resolvedCashBalance()
        let remainingCash = resolvedCash - allocatedInstitutionCash
        if abs(remainingCash) > 0.01 {
            let label = remainingCash >= 0 ? "Unassigned Cash" : "Unassigned Cash (Negative)"
            institutionValues[label, default: 0] += remainingCash
        }

        let total = institutionValues.values.reduce(0, +)
        guard abs(total) > 0.01 else { return [] }

        return institutionValues.map { name, value in
            InstitutionAllocation(
                name: name,
                value: value,
                percentage: total != 0 ? (value / total) * 100 : 0
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

struct InstitutionAllocation {
    let name: String
    let value: Double
    let percentage: Double
}

private extension PortfolioViewModel {
    func normalizedInstitutionName(_ institution: Institution?) -> String {
        let trimmed = institution?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "Unnamed Institution" }
        return trimmed
    }

    func latestInstitution(for asset: Asset, in portfolio: Portfolio) -> Institution? {
        guard let transactions = asset.transactions?.allObjects as? [Transaction] else { return nil }
        let filtered = transactions.filter {
            $0.portfolio?.objectID == portfolio.objectID && $0.institution != nil
        }
        let sorted = filtered.sorted { lhs, rhs in
            let leftDate = lhs.transactionDate ?? Date.distantPast
            let rightDate = rhs.transactionDate ?? Date.distantPast
            return leftDate > rightDate
        }
        return sorted.first?.institution
    }
}
