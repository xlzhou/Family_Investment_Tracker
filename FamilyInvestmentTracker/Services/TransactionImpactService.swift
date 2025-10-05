import CoreData
import Foundation

struct TransactionImpactService {
    private static let currencyService = CurrencyService.shared
    
    static func reverse(_ transaction: Transaction,
                       in portfolio: Portfolio,
                       context: NSManagedObjectContext,
                       preserveAsset: Bool = false) {
        // Defensive check for transaction validity
        guard let transactionType = TransactionType(rawValue: transaction.type ?? "") else {
            return
        }

        // Defensive check for Core Data consistency
        guard !transaction.isDeleted, !portfolio.isDeleted else {
            return
        }
        let portfolioCurrency = currency(for: portfolio)
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let cashDisciplineEnabled = portfolio.enforcesCashDisciplineEnabled
        let institution = transaction.value(forKey: "institution") as? Institution
        let isAmountOnly = transactionType == .dividend || transactionType == .interest || transactionType == .deposit || transactionType == .insurance || transactionType == .depositWithdrawal
        let companionDeposit = CashDisciplineService.findCompanionDeposit(for: transaction, in: context)
        if let companionDeposit {
            reverse(companionDeposit, in: portfolio, context: context)
            context.delete(companionDeposit)
        }
        let handledByCompanion = companionDeposit != nil
        
        if isAmountOnly {
            let originalNetCash = transaction.amount - transaction.fees - transaction.tax
            let netCash = currencyService.convertAmount(originalNetCash, from: transactionCurrency, to: portfolioCurrency)
            switch transactionType {
            case .deposit:
                portfolio.addToCash(-netCash)
                if let institution = institution {
                    institution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: -originalNetCash)
                }
            case .insurance:
                cleanupInsuranceArtifacts(for: transaction,
                                          in: portfolio,
                                          context: context,
                                          preserveAsset: preserveAsset)
            case .dividend, .interest:
                if let institution = institution {
                    institution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: -originalNetCash)
                } else {
                    portfolio.addToCash(-netCash)
                }
                if let asset = transaction.asset,
                   let holding = findHolding(for: asset, portfolio: portfolio, context: context) {
                    let dividendValue = currencyService.convertAmount(transaction.amount, from: transactionCurrency, to: portfolioCurrency)
                    holding.totalDividends = max(0, holding.totalDividends - dividendValue)
                    holding.updatedAt = Date()
                }
            case .depositWithdrawal:
                // For deposit withdrawals, we need to handle both the cash movement and the holding adjustment
                let originalNetCash = transaction.amount - transaction.fees - transaction.tax
                let netCash = currencyService.convertAmount(originalNetCash, from: transactionCurrency, to: portfolioCurrency)

                // Add cash back to available balance
                portfolio.addToCash(netCash)
                if let institution = institution {
                    institution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: originalNetCash)
                }

                // If this is linked to a fixed deposit, adjust the holding
                if let asset = transaction.asset,
                   let holding = findHolding(for: asset, portfolio: portfolio, context: context),
                   let parentAsset = transaction.parentDepositAsset {

                    // For fixed deposit withdrawals, we need to reduce the holding quantity
                    let withdrawalAmount = transaction.amount
                    let currentPrice = parentAsset.currentPrice
                    let quantityToRemove = withdrawalAmount / currentPrice

                    holding.quantity = max(0, holding.quantity - quantityToRemove)
                    holding.updatedAt = Date()
                }
            default:
                break
            }
        } else {
            if let asset = transaction.asset {
                reverseHoldingImpact(for: asset, transaction: transaction, transactionType: transactionType, portfolio: portfolio, context: context)
                if transactionType == .sell {
                    let originalProceeds = transaction.amount - transaction.fees - transaction.tax
                    let netProceeds = currencyService.convertAmount(originalProceeds, from: transactionCurrency, to: portfolioCurrency)
                    if netProceeds != 0, !handledByCompanion {
                        portfolio.addToCash(-netProceeds)
                        if cashDisciplineEnabled, let institution = institution {
                            institution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: -originalProceeds)
                        }
                    }
                } else if transactionType == .buy {
                    let originalCost = (transaction.quantity * transaction.price) + transaction.fees + transaction.tax
                    let cost = currencyService.convertAmount(originalCost, from: transactionCurrency, to: portfolioCurrency)
                    if cashDisciplineEnabled, !handledByCompanion {
                        portfolio.addToCash(cost)
                        if let institution = institution {
                            institution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: originalCost)
                        }
                    }
                } else if transactionType == .insurance {
                    cleanupInsuranceArtifacts(for: transaction,
                                              in: portfolio,
                                              context: context,
                                              preserveAsset: preserveAsset)
                }
            }
        }

        recomputePortfolioTotals(for: portfolio)
    }
    
    static func recomputePortfolioTotals(for portfolio: Portfolio) {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let totalHoldings = holdings.reduce(0.0) { partial, holding in
            guard let asset = holding.asset else { return partial }
            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return partial + cashValue
            }
            return partial + (holding.quantity * asset.currentPrice)
        }
        let cashBalance = portfolio.getTotalCashBalanceInMainCurrency()
        portfolio.totalValue = totalHoldings + cashBalance
        portfolio.updatedAt = Date()
    }
    
    private static func currency(for portfolio: Portfolio) -> Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private static func findHolding(for asset: Asset, portfolio: Portfolio, context: NSManagedObjectContext) -> Holding? {
        let request: NSFetchRequest<Holding> = Holding.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", asset, portfolio)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    private static func reverseHoldingImpact(for asset: Asset, transaction: Transaction, transactionType: TransactionType, portfolio: Portfolio, context: NSManagedObjectContext) {
        guard let holding = findHolding(for: asset, portfolio: portfolio, context: context) else { return }
        let portfolioCurrency = currency(for: portfolio)
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let priceInPortfolio = currencyService.convertAmount(transaction.price, from: transactionCurrency, to: portfolioCurrency)
        
        switch transactionType {
        case .buy:
            let feesInPortfolio = currencyService.convertAmount(transaction.fees, from: transactionCurrency, to: portfolioCurrency)
            let taxInPortfolio = currencyService.convertAmount(transaction.tax, from: transactionCurrency, to: portfolioCurrency)
            let transactionCost = (transaction.quantity * priceInPortfolio) + feesInPortfolio + taxInPortfolio
            let currentTotalCost = holding.quantity * holding.averageCostBasis
            let newQuantity = holding.quantity - transaction.quantity
            if newQuantity > 0 {
                let newTotalCost = currentTotalCost - transactionCost
                holding.averageCostBasis = newTotalCost / newQuantity
                holding.quantity = newQuantity
            } else {
                holding.quantity = 0
                holding.averageCostBasis = 0
            }
        case .sell:
            let currentQuantity = holding.quantity
            let currentTotalCost = holding.quantity * holding.averageCostBasis
            let feesInPortfolio = currencyService.convertAmount(transaction.fees, from: transactionCurrency, to: portfolioCurrency)
            let taxInPortfolio = currencyService.convertAmount(transaction.tax, from: transactionCurrency, to: portfolioCurrency)
            let grossProceeds = transaction.quantity * priceInPortfolio
            let realizedGain = transaction.realizedGainAmount
            let previousTotalCost = grossProceeds - feesInPortfolio - taxInPortfolio - realizedGain

            holding.quantity += transaction.quantity

            let newTotalCost = currentTotalCost + previousTotalCost
            if holding.quantity > 0 {
                holding.averageCostBasis = newTotalCost / holding.quantity
            } else {
                holding.averageCostBasis = 0
            }

            holding.realizedGainLoss -= realizedGain
        default:
            break
        }
        holding.updatedAt = Date()
    }
    
    private static func cleanupInsuranceArtifacts(for transaction: Transaction,
                                                   in portfolio: Portfolio,
                                                   context: NSManagedObjectContext,
                                                   preserveAsset: Bool) {
        guard transaction.type == TransactionType.insurance.rawValue else { return }
        let paymentDeducted = (transaction.value(forKey: "paymentDeducted") as? Bool) ?? false
        if paymentDeducted {
            let amount = (transaction.value(forKey: "paymentDeductedAmount") as? Double) ?? 0
            if amount != 0 {
                portfolio.addToCash(amount)
                if let name = transaction.value(forKey: "paymentInstitutionName") as? String,
                   let paymentInstitution = findInstitution(named: name, context: context) {
                    let portfolioCurrency = currency(for: portfolio)
                    let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
                    let originalAmount = currencyService.convertAmount(amount, from: portfolioCurrency, to: transactionCurrency)
                    paymentInstitution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: originalAmount)
                }
            }
            transaction.setValue(false, forKey: "paymentDeducted")
            transaction.setValue(0.0, forKey: "paymentDeductedAmount")
        }
        
        if let asset = transaction.asset {
            if let holding = findHolding(for: asset, portfolio: portfolio, context: context) {
                let holdingsSet = portfolio.mutableSetValue(forKey: "holdings")
                holdingsSet.remove(holding)
                context.delete(holding)
            }
            
            if let insurance = asset.value(forKey: "insurance") as? NSManagedObject {
                if let beneficiaries = insurance.value(forKey: "beneficiaries") as? Set<NSManagedObject> {
                    beneficiaries.forEach { context.delete($0) }
                }
                context.delete(insurance)
            }
            
            if !preserveAsset {
                context.delete(asset)
            }
        }
    }
    
    private static func findInstitution(named name: String, context: NSManagedObjectContext) -> Institution? {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
