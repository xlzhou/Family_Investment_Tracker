import Foundation
import CoreData
import SwiftUI

class PortfolioViewModel: ObservableObject {
    @Published var isUpdatingPrices = false

    private let marketDataService = MarketDataService.shared
    private let currencyService = CurrencyService.shared

    private struct PerformanceCacheKey: Hashable {
        let portfolioURI: String
        let days: Int
    }

    private struct DividendCacheKey: Hashable {
        let portfolioURI: String
        let months: Int
    }

    private var performanceHistoryCache: [PerformanceCacheKey: [PerformanceDataPoint]] = [:]
    private var dividendHistoryCache: [DividendCacheKey: [DividendDataPoint]] = [:]
    
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

            asset.migrateAutoFetchPreferenceIfNeeded(limitTo: portfolio)

            let hasAutoFetchEnabled = asset.resolvedAutoFetchPreference

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
    func calculatePortfolioPerformance(portfolio: Portfolio,
                                       includeInsuranceInPerformance: Bool = DashboardSettingsService.shared.includeInsuranceInPerformance) -> PortfolioPerformance {
        let holdings = portfolio.holdings?.allObjects as? [Holding] ?? []
        
        let context = portfolio.managedObjectContext ?? PersistenceController.shared.container.viewContext

        var holdingsCurrentValue: Double = 0
        var totalCostBasis: Double = 0
        var unrealizedGainLoss: Double = 0
        let realizedBreakdown = RealizedPnLCalculator.breakdownLifetime(for: portfolio,
                                                                        context: context)
        var totalDividends: Double = 0
        let totalRealizedGains = realizedBreakdown.soldAssets.reduce(0) { $0 + $1.incomeIncludedPnL }

        for holding in holdings {
            guard let asset = holding.asset else { continue }

            // Deposit assets are represented via cash balances, not holdings valuation
            if asset.assetType == AssetType.deposit.rawValue {
                totalDividends += holding.totalDividends
                continue
            }

            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = (holding.value(forKey: "cashValue") as? Double) ?? 0
                holdingsCurrentValue += cashValue
                if includeInsuranceInPerformance {
                    let paidPremium = InsurancePaymentService.totalPaidAmount(for: asset, in: portfolio, context: context)
                    totalCostBasis += paidPremium
                    unrealizedGainLoss += cashValue - paidPremium
                }
                totalDividends += holding.totalDividends
                continue
            }

            let currentValue = holding.quantity * asset.currentPrice
            let costBasis = holding.quantity * holding.averageCostBasis
            holdingsCurrentValue += currentValue
            totalCostBasis += costBasis
            unrealizedGainLoss += currentValue - costBasis
            totalDividends += holding.totalDividends
        }

        //print("[PortfolioPerformance] Lifetime realized via calculator:", totalRealizedGains,
        //      "Dividends/interest:", totalDividends)

        let totalCashBalance = portfolio.totalCashBalance
        let totalCurrentValue = holdingsCurrentValue + totalCashBalance

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
            let cash = institution.getCashBalance(for: portfolio)
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

    @MainActor
    func performanceHistory(for portfolio: Portfolio, days: Int = 90) -> [PerformanceDataPoint] {
        let portfolioURI = portfolio.objectID.uriRepresentation().absoluteString
        let cacheKey = PerformanceCacheKey(portfolioURI: portfolioURI, days: days)
        if let cached = performanceHistoryCache[cacheKey] {
            return cached
        }

        let history = computePerformanceHistory(for: portfolio, days: days)
        performanceHistoryCache[cacheKey] = history
        return history
    }

    @MainActor
    func dividendHistory(for portfolio: Portfolio, months: Int = 12) -> [DividendDataPoint] {
        let portfolioURI = portfolio.objectID.uriRepresentation().absoluteString
        let cacheKey = DividendCacheKey(portfolioURI: portfolioURI, months: months)
        if let cached = dividendHistoryCache[cacheKey] {
            return cached
        }

        let history = computeDividendHistory(for: portfolio, months: months)
        dividendHistoryCache[cacheKey] = history
        return history
    }

    @MainActor
    func invalidateAnalyticsCache(for portfolio: Portfolio) {
        let uri = portfolio.objectID.uriRepresentation().absoluteString
        performanceHistoryCache.keys
            .filter { $0.portfolioURI == uri }
            .forEach { performanceHistoryCache.removeValue(forKey: $0) }
        dividendHistoryCache.keys
            .filter { $0.portfolioURI == uri }
            .forEach { dividendHistoryCache.removeValue(forKey: $0) }
    }

    private func computePerformanceHistory(for portfolio: Portfolio, days: Int) -> [PerformanceDataPoint] {
        guard days > 0 else { return [] }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let sortedTransactions = transactions.sorted { lhs, rhs in
            let leftDate = lhs.transactionDate ?? lhs.createdAt ?? Date.distantPast
            let rightDate = rhs.transactionDate ?? rhs.createdAt ?? Date.distantPast
            return leftDate < rightDate
        }

        var assetQuantities: [NSManagedObjectID: Double] = [:]
        var assetReferenceCache: [NSManagedObjectID: Asset] = [:]
        var cashBalance: Double = 0

        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd

        func asset(for id: NSManagedObjectID) -> Asset? {
            if let cached = assetReferenceCache[id] { return cached }
            guard let asset = try? portfolio.managedObjectContext?.existingObject(with: id) as? Asset else { return nil }
            assetReferenceCache[id] = asset
            return asset
        }

        func currentValueEstimate() -> Double {
            var total = cashBalance
            for (assetID, quantity) in assetQuantities where abs(quantity) > 1e-6 {
                guard let asset = asset(for: assetID) else { continue }
                let price = asset.currentPrice
                total += quantity * price
            }
            return total
        }

        var history: [PerformanceDataPoint] = []
        var initialRecorded = false

        for transaction in sortedTransactions {
            apply(transaction: transaction,
                  to: &assetQuantities,
                  cashBalance: &cashBalance,
                  portfolioCurrency: portfolioCurrency)

            let transactionDate = transaction.transactionDate ?? transaction.createdAt ?? Date()

            if transactionDate < startDate { continue }

            if !initialRecorded {
                let initialValue = currentValueEstimate()
                history.append(PerformanceDataPoint(date: startDate, value: initialValue))
                initialRecorded = true
            }

            let value = currentValueEstimate()
            history.append(PerformanceDataPoint(date: min(transactionDate, endDate), value: value))
        }

        if history.isEmpty {
            let currentPerformance = calculatePortfolioPerformance(portfolio: portfolio)
            let baseline = PerformanceDataPoint(date: startDate, value: currentPerformance.currentValue)
            let endPoint = PerformanceDataPoint(date: endDate, value: currentPerformance.currentValue)
            return [baseline, endPoint]
        }

        // Ensure final point reflects latest portfolio value
        let currentPerformance = calculatePortfolioPerformance(portfolio: portfolio)
        if let last = history.last, abs(last.value - currentPerformance.currentValue) > 0.01 {
            history.append(PerformanceDataPoint(date: endDate, value: currentPerformance.currentValue))
        } else if let last = history.last, last.date < endDate {
            history.append(PerformanceDataPoint(date: endDate, value: currentPerformance.currentValue))
        }

        return history
            .sorted { $0.date < $1.date }
            .uniqued(by: { $0.date })
    }

    private func computeDividendHistory(for portfolio: Portfolio, months: Int) -> [DividendDataPoint] {
        guard months > 0 else { return [] }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startMonth = calendar.date(byAdding: .month, value: -(months - 1), to: endDate) else { return [] }

        var monthBuckets: [Date: Double] = [:]
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: startMonth)) ?? startMonth

        for offset in 0..<months {
            if let bucketDate = calendar.date(byAdding: .month, value: offset, to: currentMonthStart) {
                monthBuckets[bucketDate] = 0
            }
        }

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd

        for transaction in transactions {
            guard let type = TransactionType(rawValue: transaction.type ?? "") else { continue }
            guard type == .dividend || type == .interest else { continue }
            let date = transaction.transactionDate ?? transaction.createdAt ?? Date()
            if date < currentMonthStart || date > endDate { continue }

            let bucketDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let netAmount = transaction.amount - transaction.fees - transaction.tax
            let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
            let convertedAmount = currencyService.convertAmount(netAmount, from: transactionCurrency, to: portfolioCurrency)
            monthBuckets[bucketDate, default: 0] += convertedAmount
        }

        let sortedMonths = monthBuckets.keys.sorted()
        return sortedMonths.map { month in
            DividendDataPoint(month: month, amount: monthBuckets[month] ?? 0)
        }
    }

    private func apply(transaction: Transaction,
                       to assetQuantities: inout [NSManagedObjectID: Double],
                       cashBalance: inout Double,
                       portfolioCurrency: Currency) {
        guard let type = TransactionType(rawValue: transaction.type ?? "") else { return }
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let convertedFees = currencyService.convertAmount(transaction.fees, from: transactionCurrency, to: portfolioCurrency)
        let convertedTax = currencyService.convertAmount(transaction.tax, from: transactionCurrency, to: portfolioCurrency)

        switch type {
        case .buy:
            guard let asset = transaction.asset else { return }
            let convertedPrice = currencyService.convertAmount(transaction.price, from: transactionCurrency, to: portfolioCurrency)
            let totalCost = (transaction.quantity * convertedPrice) + convertedFees + convertedTax
            assetQuantities[asset.objectID, default: 0] += transaction.quantity
            cashBalance -= totalCost
        case .sell:
            guard let asset = transaction.asset else { return }
            let netProceeds = transaction.amount - transaction.fees - transaction.tax
            let convertedProceeds = currencyService.convertAmount(netProceeds, from: transactionCurrency, to: portfolioCurrency)
            assetQuantities[asset.objectID, default: 0] -= transaction.quantity
            cashBalance += convertedProceeds
        case .dividend, .interest, .deposit, .depositWithdrawal:
            let netAmount = transaction.amount - transaction.fees - transaction.tax
            let convertedNet = currencyService.convertAmount(netAmount, from: transactionCurrency, to: portfolioCurrency)
            cashBalance += convertedNet
        default:
            break
        }
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

private extension Array {
    func uniqued<T: Hashable>(by key: (Element) -> T) -> [Element] {
        var seen: Set<T> = []
        var reversedResult: [Element] = []
        for element in self.reversed() {
            let identifier = key(element)
            if seen.insert(identifier).inserted {
                reversedResult.append(element)
            }
        }
        return reversedResult.reversed()
    }
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
