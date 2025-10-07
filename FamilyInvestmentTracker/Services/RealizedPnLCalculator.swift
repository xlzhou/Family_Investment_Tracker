import Foundation
import CoreData

struct RealizedPnLCalculator {
    private static let currencyService = CurrencyService.shared

    struct RealizedAssetItem {
        let asset: Asset
        var realizedPnL: Double
        var incomeAmount: Double
        var incomeIncludedPnL: Double
    }

    struct DepositInterestItem {
        let symbol: String
        let amount: Double
    }

    struct ActiveIncomeItem {
        let asset: Asset
        let symbol: String
        let name: String
        let amount: Double
    }

    struct Breakdown {
        let soldAssets: [RealizedAssetItem]
        let depositInterest: [DepositInterestItem]
        let activeIncome: [ActiveIncomeItem]

        var total: Double {
            let soldTotal = soldAssets.reduce(0) { $0 + $1.incomeIncludedPnL }
            let depositTotal = depositInterest.reduce(0) { $0 + $1.amount }
            let activeTotal = activeIncome.reduce(0) { $0 + $1.amount }
            return soldTotal + depositTotal + activeTotal
        }
    }

    static func totalRealizedPnL(for portfolio: Portfolio,
                                 startDate: Date,
                                 endDate: Date,
                                 context: NSManagedObjectContext) -> Double {
        breakdown(for: portfolio,
                   startDate: startDate,
                   endDate: endDate,
                   context: context).total
    }

    static func breakdown(for portfolio: Portfolio,
                          startDate: Date,
                          endDate: Date,
                          context: NSManagedObjectContext) -> Breakdown {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard let inclusiveEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) else {
            return Breakdown(soldAssets: [], depositInterest: [], activeIncome: [])
        }

        let assetData = assetsWithRealizedTransactions(for: portfolio,
                                                       start: startOfDay,
                                                       end: inclusiveEnd,
                                                       context: context)
        let depositInterest = depositInterestItems(for: portfolio,
                                                   start: startOfDay,
                                                   end: inclusiveEnd)
        let activeIncome = pureDividendsAndInterest(for: portfolio,
                                                    start: startOfDay,
                                                    end: inclusiveEnd,
                                                    soldAssets: Set(assetData.map { $0.asset }))

        return Breakdown(soldAssets: assetData,
                         depositInterest: depositInterest,
                         activeIncome: activeIncome)
    }

    private static func assetsWithRealizedTransactions(for portfolio: Portfolio,
                                                       start: Date,
                                                       end: Date,
                                                       context: NSManagedObjectContext) -> [RealizedAssetItem] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        let sellTransactions = transactions.filter { transaction in
            guard let date = transaction.transactionDate else { return false }
            guard date >= start && date <= end else { return false }
            return TransactionType(rawValue: transaction.type ?? "") == .sell
        }

        var assetDataMap: [Asset: RealizedAssetItem] = [:]

        for transaction in sellTransactions {
            guard let asset = transaction.asset else { continue }
            if assetDataMap[asset] == nil {
                assetDataMap[asset] = RealizedAssetItem(asset: asset,
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
            .sorted { ($0.asset.symbol ?? $0.asset.name ?? "") < ($1.asset.symbol ?? $1.asset.name ?? "") }
    }

    private static func depositInterestItems(for portfolio: Portfolio,
                                             start: Date,
                                             end: Date) -> [DepositInterestItem] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        var depositGroups: [String: Double] = [:]

        for transaction in transactions {
            guard let date = transaction.transactionDate else { continue }
            guard date >= start && date <= end else { continue }

            guard let type = TransactionType(rawValue: transaction.type ?? ""), type == .interest else {
                continue
            }

            guard let asset = transaction.asset,
                  asset.assetType == AssetType.deposit.rawValue else {
                continue
            }

            let institutionName = transaction.institution?.name ?? "Unknown Institution"
            let isFromFixedDeposit = asset.isFixedDeposit == true
            let depositType = isFromFixedDeposit ? "Fixed Deposits" : "Demand Deposits"
            let key = "\(institutionName) - \(depositType)"

            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net,
                                                             transactionCurrencyCode: transaction.currency,
                                                             portfolio: portfolio)
            depositGroups[key, default: 0] += convertedAmount
        }

        return depositGroups.map { key, amount in
            DepositInterestItem(symbol: key, amount: amount)
        }.sorted { $0.symbol < $1.symbol }
    }

    private static func convertToPortfolioCurrency(_ amount: Double,
                                                    transactionCurrencyCode: String?,
                                                    portfolio: Portfolio) -> Double {
        let portfolioCurrency = Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd
        let transactionCurrency = Currency(rawValue: transactionCurrencyCode ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        return currencyService.convertAmount(amount, from: transactionCurrency, to: portfolioCurrency)
    }

    private static func pureDividendsAndInterest(for portfolio: Portfolio,
                                                 start: Date,
                                                 end: Date,
                                                 soldAssets: Set<Asset>) -> [ActiveIncomeItem] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        return transactions.reduce(into: [Asset: Double]()) { result, transaction in
            guard let date = transaction.transactionDate else { return }
            guard date >= start && date <= end else { return }
            guard let asset = transaction.asset else { return }

            guard !soldAssets.contains(asset) else { return }

            guard let type = TransactionType(rawValue: transaction.type ?? ""),
                  type == .dividend || type == .interest else { return }

            guard asset.assetType != AssetType.deposit.rawValue else { return }

            let net = transaction.amount - transaction.fees - transaction.tax
            let convertedAmount = convertToPortfolioCurrency(net,
                                                             transactionCurrencyCode: transaction.currency,
                                                             portfolio: portfolio)
            result[asset, default: 0] += convertedAmount
        }.map { asset, amount in
            let symbol = asset.symbol ?? asset.name ?? "Unknown"
            let name = asset.name ?? "Unknown"
            return ActiveIncomeItem(asset: asset,
                                    symbol: symbol,
                                    name: name,
                                    amount: amount)
        }.sorted { $0.symbol < $1.symbol }
    }
}
