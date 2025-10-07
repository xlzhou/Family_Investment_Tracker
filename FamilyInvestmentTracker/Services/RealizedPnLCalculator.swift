import Foundation
import CoreData

struct RealizedPnLCalculator {
    private static let currencyService = CurrencyService.shared

    static func totalRealizedPnL(for portfolio: Portfolio,
                                 startDate: Date,
                                 endDate: Date,
                                 context: NSManagedObjectContext) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let inclusiveEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return 0
        }

        let assetData = assetsWithRealizedTransactions(for: portfolio,
                                                       start: startOfDay,
                                                       end: inclusiveEnd,
                                                       context: context)
        let depositInterest = depositInterestItems(for: portfolio,
                                                   start: startOfDay,
                                                   end: inclusiveEnd)

        let assetTotal = assetData.reduce(0) { $0 + $1.incomeIncludedPnL }
        let depositTotal = depositInterest.reduce(0) { $0 + $1.amount }
        return assetTotal + depositTotal
    }

    private static func assetsWithRealizedTransactions(for portfolio: Portfolio,
                                                       start: Date,
                                                       end: Date,
                                                       context: NSManagedObjectContext) -> [CalculatorAssetRealizedData] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        let sellTransactions = transactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }
            return TransactionType(rawValue: transaction.type ?? "") == .sell
        }

        var assetDataMap: [Asset: CalculatorAssetRealizedData] = [:]

        for transaction in sellTransactions {
            guard let asset = transaction.asset else { continue }
            if assetDataMap[asset] == nil {
                assetDataMap[asset] = CalculatorAssetRealizedData(asset: asset,
                                                                  realizedPnL: 0,
                                                                  incomeAmount: 0,
                                                                  incomeIncludedPnL: 0)
            }

            let realizedGain = transaction.realizedGainAmount
            assetDataMap[asset]?.realizedPnL += realizedGain
            assetDataMap[asset]?.incomeIncludedPnL += realizedGain
        }

        let soldAssets = Set(assetDataMap.keys)
        let incomeTransactions = transactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }
            guard let asset = transaction.asset else { return false }
            guard soldAssets.contains(asset) else { return false }

            let type = TransactionType(rawValue: transaction.type ?? "")
            return type == .dividend || type == .interest
        }

        for transaction in incomeTransactions {
            guard let asset = transaction.asset else { continue }
            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net,
                                                             transactionCurrencyCode: transaction.currency,
                                                             portfolio: portfolio)
            assetDataMap[asset]?.incomeAmount += convertedAmount
            assetDataMap[asset]?.incomeIncludedPnL += convertedAmount
        }

        return Array(assetDataMap.values).filter { $0.realizedPnL != 0 || $0.incomeIncludedPnL != 0 }
    }

    private static func depositInterestItems(for portfolio: Portfolio,
                                             start: Date,
                                             end: Date) -> [DepositInterestItem] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        return transactions.compactMap { transaction -> DepositInterestItem? in
            guard let date = transaction.transactionDate else { return nil }
            guard date >= start && date <= end else { return nil }

            guard let type = TransactionType(rawValue: transaction.type ?? ""), type == .interest else {
                return nil
            }

            guard let asset = transaction.asset,
                  asset.assetType == AssetType.deposit.rawValue else {
                return nil
            }

            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net,
                                                             transactionCurrencyCode: transaction.currency,
                                                             portfolio: portfolio)
            return DepositInterestItem(amount: convertedAmount)
        }
    }

    private static func convertToPortfolioCurrency(_ amount: Double,
                                                    transactionCurrencyCode: String?,
                                                    portfolio: Portfolio) -> Double {
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd
        let transactionCurrency = Currency(rawValue: transactionCurrencyCode ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        return currencyService.convertAmount(amount, from: transactionCurrency, to: portfolioCurrency)
    }
}

private struct CalculatorAssetRealizedData {
    let asset: Asset
    var realizedPnL: Double
    var incomeAmount: Double
    var incomeIncludedPnL: Double
}

private struct DepositInterestItem {
    let amount: Double
}
