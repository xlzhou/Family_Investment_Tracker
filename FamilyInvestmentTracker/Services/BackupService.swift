import Foundation
import CoreData

struct BackupPackage: Codable {
    let version: Int
    let generatedAt: Date
    let portfolios: [BackupPortfolio]
    let holdings: [BackupHolding]
    let assets: [BackupAsset]
    let transactions: [BackupTransaction]
    let institutions: [BackupInstitution]
    let insurances: [BackupInsurance]
    let portfolioInstitutionCurrencyCash: [BackupPortfolioInstitutionCurrencyCash]
    let dashboardCurrencyCode: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case generatedAt
        case portfolios
        case holdings
        case assets
        case transactions
        case institutions
        case insurances
        case portfolioInstitutionCurrencyCash
        case legacyPortfolioInstitutionCash = "portfolioInstitutionCash"
        case dashboardCurrencyCode
    }

    init(version: Int,
         generatedAt: Date,
         portfolios: [BackupPortfolio],
         holdings: [BackupHolding],
         assets: [BackupAsset],
         transactions: [BackupTransaction],
         institutions: [BackupInstitution],
         insurances: [BackupInsurance],
         portfolioInstitutionCurrencyCash: [BackupPortfolioInstitutionCurrencyCash],
         dashboardCurrencyCode: String?) {
        self.version = version
        self.generatedAt = generatedAt
        self.portfolios = portfolios
        self.holdings = holdings
        self.assets = assets
        self.transactions = transactions
        self.institutions = institutions
        self.insurances = insurances
        self.portfolioInstitutionCurrencyCash = portfolioInstitutionCurrencyCash
        self.dashboardCurrencyCode = dashboardCurrencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let decodedPortfolios = try container.decode([BackupPortfolio].self, forKey: .portfolios)
        portfolios = decodedPortfolios
        holdings = try container.decode([BackupHolding].self, forKey: .holdings)
        assets = try container.decode([BackupAsset].self, forKey: .assets)
        transactions = try container.decode([BackupTransaction].self, forKey: .transactions)
        institutions = try container.decode([BackupInstitution].self, forKey: .institutions)
        insurances = try container.decodeIfPresent([BackupInsurance].self, forKey: .insurances) ?? []

        if let currencyCash = try container.decodeIfPresent([BackupPortfolioInstitutionCurrencyCash].self, forKey: .portfolioInstitutionCurrencyCash) {
            portfolioInstitutionCurrencyCash = currencyCash
        } else if let legacyCash = try container.decodeIfPresent([LegacyPortfolioInstitutionCash].self, forKey: .legacyPortfolioInstitutionCash) {
            let portfolioCurrencyMap = Dictionary(uniqueKeysWithValues: decodedPortfolios.map { ($0.id, $0.mainCurrency ?? "USD") })
            portfolioInstitutionCurrencyCash = legacyCash.map { legacy in
                let currency = portfolioCurrencyMap[legacy.portfolioID] ?? "USD"
                return BackupPortfolioInstitutionCurrencyCash(
                    id: legacy.id,
                    portfolioID: legacy.portfolioID,
                    institutionID: legacy.institutionID,
                    currency: currency,
                    amount: legacy.cashBalance,
                    createdAt: legacy.createdAt,
                    updatedAt: legacy.updatedAt
                )
            }
        } else {
            portfolioInstitutionCurrencyCash = []
        }

        dashboardCurrencyCode = try container.decodeIfPresent(String.self, forKey: .dashboardCurrencyCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(portfolios, forKey: .portfolios)
        try container.encode(holdings, forKey: .holdings)
        try container.encode(assets, forKey: .assets)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(institutions, forKey: .institutions)
        try container.encode(insurances, forKey: .insurances)
        try container.encode(portfolioInstitutionCurrencyCash, forKey: .portfolioInstitutionCurrencyCash)
        try container.encodeIfPresent(dashboardCurrencyCode, forKey: .dashboardCurrencyCode)
    }
}

struct BackupPortfolio: Codable {
    let id: UUID
    let name: String?
    let createdAt: Date?
    let updatedAt: Date?
    let mainCurrency: String?
    let totalValue: Double
    let enforcesCashDiscipline: Bool
    let ownerID: String?

    init(id: UUID,
         name: String?,
         createdAt: Date?,
         updatedAt: Date?,
         mainCurrency: String?,
         totalValue: Double,
         enforcesCashDiscipline: Bool,
         ownerID: String?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mainCurrency = mainCurrency
        self.totalValue = totalValue
        self.enforcesCashDiscipline = enforcesCashDiscipline
        self.ownerID = ownerID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, mainCurrency, totalValue, enforcesCashDiscipline, ownerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        mainCurrency = try container.decodeIfPresent(String.self, forKey: .mainCurrency)
        totalValue = try container.decode(Double.self, forKey: .totalValue)
        enforcesCashDiscipline = try container.decodeIfPresent(Bool.self, forKey: .enforcesCashDiscipline) ?? true
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(mainCurrency, forKey: .mainCurrency)
        try container.encode(totalValue, forKey: .totalValue)
        try container.encode(enforcesCashDiscipline, forKey: .enforcesCashDiscipline)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
    }
}

struct BackupHolding: Codable {
    let id: UUID
    let portfolioID: UUID?
    let assetID: UUID?
    let institutionID: UUID?
    let quantity: Double
    let averageCostBasis: Double
    let totalDividends: Double
    let realizedGainLoss: Double
    let updatedAt: Date?
    let cashValue: Double?
}

struct BackupAsset: Codable {
    let id: UUID
    let symbol: String?
    let name: String?
    let assetType: String?
    let createdAt: Date?
    let currentPrice: Double
    let lastPriceUpdate: Date?
    let interestRate: Double?
    let linkedAssets: String?
    let autoFetchPriceEnabled: Bool
    // Fixed deposit specific fields
    let depositSubtype: String?
    let maturityDate: Date?
    let allowEarlyWithdrawal: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, symbol, name, assetType, createdAt, currentPrice, lastPriceUpdate, interestRate, linkedAssets, autoFetchPriceEnabled, depositSubtype, maturityDate, allowEarlyWithdrawal
    }

    init(id: UUID,
         symbol: String?,
         name: String?,
         assetType: String?,
         createdAt: Date?,
         currentPrice: Double,
         lastPriceUpdate: Date?,
         interestRate: Double?,
         linkedAssets: String?,
         autoFetchPriceEnabled: Bool,
         depositSubtype: String? = nil,
         maturityDate: Date? = nil,
         allowEarlyWithdrawal: Bool? = nil) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.assetType = assetType
        self.createdAt = createdAt
        self.currentPrice = currentPrice
        self.lastPriceUpdate = lastPriceUpdate
        self.interestRate = interestRate
        self.linkedAssets = linkedAssets
        self.autoFetchPriceEnabled = autoFetchPriceEnabled
        self.depositSubtype = depositSubtype
        self.maturityDate = maturityDate
        self.allowEarlyWithdrawal = allowEarlyWithdrawal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        assetType = try container.decodeIfPresent(String.self, forKey: .assetType)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        currentPrice = try container.decode(Double.self, forKey: .currentPrice)
        lastPriceUpdate = try container.decodeIfPresent(Date.self, forKey: .lastPriceUpdate)
        interestRate = try container.decodeIfPresent(Double.self, forKey: .interestRate)
        linkedAssets = try container.decodeIfPresent(String.self, forKey: .linkedAssets)
        autoFetchPriceEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFetchPriceEnabled) ?? false
        // Fixed deposit specific fields (backwards compatible)
        depositSubtype = try container.decodeIfPresent(String.self, forKey: .depositSubtype)
        maturityDate = try container.decodeIfPresent(Date.self, forKey: .maturityDate)
        allowEarlyWithdrawal = try container.decodeIfPresent(Bool.self, forKey: .allowEarlyWithdrawal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(assetType, forKey: .assetType)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(currentPrice, forKey: .currentPrice)
        try container.encodeIfPresent(lastPriceUpdate, forKey: .lastPriceUpdate)
        try container.encodeIfPresent(interestRate, forKey: .interestRate)
        try container.encodeIfPresent(linkedAssets, forKey: .linkedAssets)
        try container.encode(autoFetchPriceEnabled, forKey: .autoFetchPriceEnabled)
        // Fixed deposit specific fields
        try container.encodeIfPresent(depositSubtype, forKey: .depositSubtype)
        try container.encodeIfPresent(maturityDate, forKey: .maturityDate)
        try container.encodeIfPresent(allowEarlyWithdrawal, forKey: .allowEarlyWithdrawal)
    }
}

struct BackupTransaction: Codable {
    let id: UUID
    let portfolioID: UUID?
    let assetID: UUID?
    let institutionID: UUID?
    let type: String?
    let transactionDate: Date?
    let amount: Double
    let quantity: Double
    let price: Double
    let fees: Double
    let tax: Double
    let currency: String?
    let tradingInstitution: String?
    let transactionCode: String?
    let notes: String?
    let createdAt: Date?
    let maturityDate: Date?
    let paymentInstitutionName: String?
    let paymentDeducted: Bool
    let paymentDeductedAmount: Double
    let realizedGain: Double
    let autoFetchPrice: Bool
    let interestRate: Double
    let linkedInsuranceAssetID: UUID?
    let linkedTransactionID: UUID?
    let parentDepositAssetID: UUID?
    let accruedInterest: Double
    let institutionPenalty: Double

    init(id: UUID,
         portfolioID: UUID?,
         assetID: UUID?,
         institutionID: UUID?,
         type: String?,
         transactionDate: Date?,
         amount: Double,
         quantity: Double,
         price: Double,
         fees: Double,
         tax: Double,
         currency: String?,
         tradingInstitution: String?,
         transactionCode: String?,
         notes: String?,
         createdAt: Date?,
         maturityDate: Date?,
         paymentInstitutionName: String?,
         paymentDeducted: Bool,
         paymentDeductedAmount: Double,
         realizedGain: Double,
         autoFetchPrice: Bool,
         interestRate: Double,
         linkedInsuranceAssetID: UUID?,
         linkedTransactionID: UUID?,
         parentDepositAssetID: UUID?,
         accruedInterest: Double,
         institutionPenalty: Double) {
        self.id = id
        self.portfolioID = portfolioID
        self.assetID = assetID
        self.institutionID = institutionID
        self.type = type
        self.transactionDate = transactionDate
        self.amount = amount
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.tax = tax
        self.currency = currency
        self.tradingInstitution = tradingInstitution
        self.transactionCode = transactionCode
        self.notes = notes
        self.createdAt = createdAt
        self.maturityDate = maturityDate
        self.paymentInstitutionName = paymentInstitutionName
        self.paymentDeducted = paymentDeducted
        self.paymentDeductedAmount = paymentDeductedAmount
        self.realizedGain = realizedGain
        self.autoFetchPrice = autoFetchPrice
        self.interestRate = interestRate
        self.linkedInsuranceAssetID = linkedInsuranceAssetID
        self.linkedTransactionID = linkedTransactionID
        self.parentDepositAssetID = parentDepositAssetID
        self.accruedInterest = accruedInterest
        self.institutionPenalty = institutionPenalty
    }

    private enum CodingKeys: String, CodingKey {
        case id, portfolioID, assetID, institutionID, type, transactionDate, amount, quantity, price, fees, tax, currency, tradingInstitution, transactionCode, notes, createdAt, maturityDate, paymentInstitutionName, paymentDeducted, paymentDeductedAmount, realizedGain, autoFetchPrice, interestRate, linkedInsuranceAssetID, linkedTransactionID, parentDepositAssetID, accruedInterest, institutionPenalty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        portfolioID = try container.decodeIfPresent(UUID.self, forKey: .portfolioID)
        assetID = try container.decodeIfPresent(UUID.self, forKey: .assetID)
        institutionID = try container.decodeIfPresent(UUID.self, forKey: .institutionID)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        transactionDate = try container.decodeIfPresent(Date.self, forKey: .transactionDate)
        amount = try container.decode(Double.self, forKey: .amount)
        quantity = try container.decode(Double.self, forKey: .quantity)
        price = try container.decode(Double.self, forKey: .price)
        fees = try container.decode(Double.self, forKey: .fees)
        tax = try container.decode(Double.self, forKey: .tax)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        tradingInstitution = try container.decodeIfPresent(String.self, forKey: .tradingInstitution)
        transactionCode = try container.decodeIfPresent(String.self, forKey: .transactionCode)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        maturityDate = try container.decodeIfPresent(Date.self, forKey: .maturityDate)
        paymentInstitutionName = try container.decodeIfPresent(String.self, forKey: .paymentInstitutionName)
        paymentDeducted = try container.decode(Bool.self, forKey: .paymentDeducted)
        paymentDeductedAmount = try container.decode(Double.self, forKey: .paymentDeductedAmount)
        realizedGain = try container.decode(Double.self, forKey: .realizedGain)
        autoFetchPrice = try container.decodeIfPresent(Bool.self, forKey: .autoFetchPrice) ?? false
        interestRate = try container.decodeIfPresent(Double.self, forKey: .interestRate) ?? 0
        linkedInsuranceAssetID = try container.decodeIfPresent(UUID.self, forKey: .linkedInsuranceAssetID)
        linkedTransactionID = try container.decodeIfPresent(UUID.self, forKey: .linkedTransactionID)
        parentDepositAssetID = try container.decodeIfPresent(UUID.self, forKey: .parentDepositAssetID)
        accruedInterest = try container.decodeIfPresent(Double.self, forKey: .accruedInterest) ?? 0
        institutionPenalty = try container.decodeIfPresent(Double.self, forKey: .institutionPenalty) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(portfolioID, forKey: .portfolioID)
        try container.encodeIfPresent(assetID, forKey: .assetID)
        try container.encodeIfPresent(institutionID, forKey: .institutionID)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(transactionDate, forKey: .transactionDate)
        try container.encode(amount, forKey: .amount)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(price, forKey: .price)
        try container.encode(fees, forKey: .fees)
        try container.encode(tax, forKey: .tax)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(tradingInstitution, forKey: .tradingInstitution)
        try container.encodeIfPresent(transactionCode, forKey: .transactionCode)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(maturityDate, forKey: .maturityDate)
        try container.encodeIfPresent(paymentInstitutionName, forKey: .paymentInstitutionName)
        try container.encode(paymentDeducted, forKey: .paymentDeducted)
        try container.encode(paymentDeductedAmount, forKey: .paymentDeductedAmount)
        try container.encode(realizedGain, forKey: .realizedGain)
        try container.encode(autoFetchPrice, forKey: .autoFetchPrice)
        try container.encode(interestRate, forKey: .interestRate)
        try container.encodeIfPresent(linkedInsuranceAssetID, forKey: .linkedInsuranceAssetID)
        try container.encodeIfPresent(linkedTransactionID, forKey: .linkedTransactionID)
        try container.encodeIfPresent(parentDepositAssetID, forKey: .parentDepositAssetID)
        try container.encode(accruedInterest, forKey: .accruedInterest)
        try container.encode(institutionPenalty, forKey: .institutionPenalty)
    }
}

struct BackupInsurance: Codable {
    let id: UUID
    let assetID: UUID
    let insuranceType: String?
    let policyholder: String?
    let insuredPerson: String?
    let contactNumber: String?
    let basicInsuredAmount: Double
    let additionalPaymentAmount: Double
    let deathBenefit: Double
    let isParticipating: Bool
    let hasSupplementaryInsurance: Bool
    let premiumPaymentTerm: Int32
    let premiumPaymentStatus: String?
    let premiumPaymentType: String?
    let singlePremium: Double
    let firstDiscountedPremium: Double?
    let totalPremium: Double
    let coverageExpirationDate: Date?
    let maturityBenefitRedemptionDate: Date?
    let estimatedMaturityBenefit: Double
    let canWithdrawPremiums: Bool
    let maxWithdrawalPercentage: Double
    let createdAt: Date?
    let beneficiaries: [BackupBeneficiary]
}

struct BackupBeneficiary: Codable {
    let id: UUID
    let insuranceID: UUID
    let name: String?
    let percentage: Double
    let createdAt: Date?
}

struct BackupInstitution: Codable {
    let id: UUID
    let name: String?
    let createdAt: Date?
}

struct BackupPortfolioInstitutionCurrencyCash: Codable {
    let id: UUID
    let portfolioID: UUID
    let institutionID: UUID
    let currency: String
    let amount: Double
    let createdAt: Date?
    let updatedAt: Date?
}

private struct LegacyPortfolioInstitutionCash: Codable {
    let id: UUID
    let portfolioID: UUID
    let institutionID: UUID
    let cashBalance: Double
    let createdAt: Date?
    let updatedAt: Date?
}

final class BackupService {
    static let shared = BackupService()
    private init() {}
    
    private let backupVersion = 6
    
    func createBackup(context: NSManagedObjectContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        var payload: BackupPackage?
        var updatedObjects = false
        
        try context.performAndWait {
            let portfolioFetch: NSFetchRequest<Portfolio> = Portfolio.fetchRequest()
            let holdingFetch: NSFetchRequest<Holding> = Holding.fetchRequest()
            let assetFetch: NSFetchRequest<Asset> = Asset.fetchRequest()
            let transactionFetch: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            let institutionFetch: NSFetchRequest<Institution> = Institution.fetchRequest()
            let portfolioInstitutionCurrencyCashFetch: NSFetchRequest<PortfolioInstitutionCurrencyCash> = PortfolioInstitutionCurrencyCash.fetchRequest()
            
            let portfolios = try context.fetch(portfolioFetch)
            let holdings = try context.fetch(holdingFetch)
            let assets = try context.fetch(assetFetch)
            let transactions = try context.fetch(transactionFetch)
            let institutions = try context.fetch(institutionFetch)
            let portfolioInstitutionCurrencyCashRecords = try context.fetch(portfolioInstitutionCurrencyCashFetch)
            
            portfolios.forEach { updatedObjects = ensureIdentifier(for: $0) || updatedObjects }
            holdings.forEach { updatedObjects = ensureIdentifier(for: $0) || updatedObjects }
            assets.forEach { updatedObjects = ensureIdentifier(for: $0) || updatedObjects }
            institutions.forEach { updatedObjects = ensureIdentifier(for: $0) || updatedObjects }
            transactions.forEach {
                updatedObjects = ensureIdentifier(for: $0) || updatedObjects
                $0.ensureIdentifiers()
            }
            
            if updatedObjects && context.hasChanges {
                try context.save()
            }
            
                payload = BackupPackage(
                    version: backupVersion,
                    generatedAt: Date(),
                    portfolios: portfolios.map { portfolio in
                        BackupPortfolio(
                            id: portfolio.id ?? UUID(),
                            name: portfolio.name,
                            createdAt: portfolio.createdAt,
                            updatedAt: portfolio.updatedAt,
                            mainCurrency: portfolio.mainCurrency,
                            totalValue: portfolio.totalValue,
                            enforcesCashDiscipline: portfolio.enforcesCashDisciplineEnabled,
                            ownerID: portfolio.ownerID
                        )
                },
                holdings: holdings.map { holding in
                    BackupHolding(
                        id: holding.id ?? UUID(),
                        portfolioID: holding.portfolio?.id,
                        assetID: holding.asset?.id,
                        institutionID: holding.institution?.id,
                        quantity: holding.quantity,
                        averageCostBasis: holding.averageCostBasis,
                        totalDividends: holding.totalDividends,
                        realizedGainLoss: holding.realizedGainLoss,
                        updatedAt: holding.updatedAt,
                        cashValue: holding.value(forKey: "cashValue") as? Double
                    )
                },
                assets: assets.map { asset in
                    BackupAsset(
                        id: asset.id ?? UUID(),
                        symbol: asset.symbol,
                        name: asset.name,
                        assetType: asset.assetType,
                        createdAt: asset.createdAt,
                        currentPrice: asset.currentPrice,
                        lastPriceUpdate: asset.lastPriceUpdate,
                        interestRate: asset.value(forKey: "interestRate") as? Double,
                        linkedAssets: asset.value(forKey: "linkedAssets") as? String,
                        autoFetchPriceEnabled: (asset.value(forKey: "autoFetchPriceEnabled") as? Bool) ?? false,
                        depositSubtype: asset.value(forKey: "depositSubtype") as? String,
                        maturityDate: asset.maturityDate,
                        allowEarlyWithdrawal: asset.value(forKey: "allowEarlyWithdrawal") as? Bool
                    )
                },
                transactions: transactions.map { transaction in
                    BackupTransaction(
                        id: transaction.id ?? UUID(),
                        portfolioID: transaction.portfolio?.id,
                        assetID: transaction.asset?.id,
                        institutionID: transaction.institution?.id,
                        type: transaction.type,
                        transactionDate: transaction.transactionDate,
                        amount: transaction.amount,
                        quantity: transaction.quantity,
                        price: transaction.price,
                        fees: transaction.fees,
                        tax: transaction.tax,
                        currency: transaction.currency,
                        tradingInstitution: transaction.tradingInstitution,
                        transactionCode: transaction.transactionCode,
                        notes: transaction.notes,
                        createdAt: transaction.createdAt,
                        maturityDate: transaction.maturityDate,
                        paymentInstitutionName: transaction.value(forKey: "paymentInstitutionName") as? String,
                        paymentDeducted: (transaction.value(forKey: "paymentDeducted") as? Bool) ?? false,
                        paymentDeductedAmount: (transaction.value(forKey: "paymentDeductedAmount") as? Double) ?? 0,
                        realizedGain: transaction.realizedGainAmount,
                        autoFetchPrice: transaction.autoFetchPrice,
                        interestRate: (transaction.value(forKey: "interestRate") as? Double) ?? 0,
                        linkedInsuranceAssetID: transaction.value(forKey: "linkedInsuranceAssetID") as? UUID,
                        linkedTransactionID: transaction.value(forKey: "linkedTransactionID") as? UUID,
                        parentDepositAssetID: transaction.value(forKey: "parentDepositAssetID") as? UUID,
                        accruedInterest: (transaction.value(forKey: "accruedInterest") as? Double) ?? 0,
                        institutionPenalty: (transaction.value(forKey: "institutionPenalty") as? Double) ?? 0
                    )
                },
                institutions: institutions.map { institution in
                    BackupInstitution(
                        id: institution.id ?? UUID(),
                        name: institution.name,
                        createdAt: institution.createdAt
                    )
                },
                insurances: assets.compactMap { asset in
                    guard let insurance = asset.value(forKey: "insurance") as? NSManagedObject,
                          let assetID = asset.id else { return nil }

                    let beneficiariesSet = insurance.value(forKey: "beneficiaries") as? Set<NSManagedObject> ?? []
                    let beneficiaries = beneficiariesSet.map { beneficiary -> BackupBeneficiary in
                        BackupBeneficiary(
                            id: (beneficiary.value(forKey: "id") as? UUID) ?? UUID(),
                            insuranceID: (insurance.value(forKey: "id") as? UUID) ?? UUID(),
                            name: beneficiary.value(forKey: "name") as? String,
                            percentage: beneficiary.value(forKey: "percentage") as? Double ?? 0,
                            createdAt: beneficiary.value(forKey: "createdAt") as? Date
                        )
                    }

                    return BackupInsurance(
                        id: (insurance.value(forKey: "id") as? UUID) ?? UUID(),
                        assetID: assetID,
                        insuranceType: insurance.value(forKey: "insuranceType") as? String,
                        policyholder: insurance.value(forKey: "policyholder") as? String,
                        insuredPerson: insurance.value(forKey: "insuredPerson") as? String,
                        contactNumber: insurance.value(forKey: "contactNumber") as? String,
                        basicInsuredAmount: insurance.value(forKey: "basicInsuredAmount") as? Double ?? 0,
                        additionalPaymentAmount: insurance.value(forKey: "additionalPaymentAmount") as? Double ?? 0,
                        deathBenefit: insurance.value(forKey: "deathBenefit") as? Double ?? 0,
                        isParticipating: insurance.value(forKey: "isParticipating") as? Bool ?? false,
                        hasSupplementaryInsurance: insurance.value(forKey: "hasSupplementaryInsurance") as? Bool ?? false,
                        premiumPaymentTerm: insurance.value(forKey: "premiumPaymentTerm") as? Int32 ?? 0,
                        premiumPaymentStatus: insurance.value(forKey: "premiumPaymentStatus") as? String,
                        premiumPaymentType: insurance.value(forKey: "premiumPaymentType") as? String,
                        singlePremium: insurance.value(forKey: "singlePremium") as? Double ?? 0,
                        firstDiscountedPremium: insurance.value(forKey: "firstDiscountedPremium") as? Double,
                        totalPremium: insurance.value(forKey: "totalPremium") as? Double ?? 0,
                        coverageExpirationDate: insurance.value(forKey: "coverageExpirationDate") as? Date,
                        maturityBenefitRedemptionDate: insurance.value(forKey: "maturityBenefitRedemptionDate") as? Date,
                        estimatedMaturityBenefit: insurance.value(forKey: "estimatedMaturityBenefit") as? Double ?? 0,
                        canWithdrawPremiums: insurance.value(forKey: "canWithdrawPremiums") as? Bool ?? false,
                        maxWithdrawalPercentage: insurance.value(forKey: "maxWithdrawalPercentage") as? Double ?? 0,
                        createdAt: insurance.value(forKey: "createdAt") as? Date,
                        beneficiaries: beneficiaries
                    )
                },
                portfolioInstitutionCurrencyCash: portfolioInstitutionCurrencyCashRecords.map { cashRecord in
                    BackupPortfolioInstitutionCurrencyCash(
                        id: cashRecord.id ?? UUID(),
                        portfolioID: cashRecord.portfolio?.id ?? UUID(),
                        institutionID: cashRecord.institution?.id ?? UUID(),
                        currency: cashRecord.currency ?? "USD",
                        amount: cashRecord.amount,
                        createdAt: cashRecord.createdAt,
                        updatedAt: cashRecord.updatedAt
                    )
                },
                dashboardCurrencyCode: DashboardSettingsService.shared.dashboardCurrency.rawValue
            )
        }
        
        guard let package = payload else {
            throw NSError(domain: "BackupService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to generate backup payload."])
        }
        
        let data = try encoder.encode(package)
        let timestamp = Self.fileTimestampFormatter.string(from: Date())
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyInvestmentBackup-\(timestamp).json")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }
    
    func restoreBackup(from url: URL, context: NSManagedObjectContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let package = try decoder.decode(BackupPackage.self, from: data)

        if let currencyCode = package.dashboardCurrencyCode,
           let currency = Currency(rawValue: currencyCode) {
            DashboardSettingsService.shared.updateCurrency(currency)
        }

        try context.performAndWait {
            try clearExistingData(in: context)
            
            var assetsDict: [UUID: Asset] = [:]
            var portfoliosDict: [UUID: Portfolio] = [:]
            var institutionsDict: [UUID: Institution] = [:]
            
            for assetData in package.assets {
                let asset = Asset(context: context)
                asset.id = assetData.id
                asset.symbol = assetData.symbol
                asset.name = assetData.name
                asset.assetType = assetData.assetType
                asset.createdAt = assetData.createdAt
                asset.currentPrice = assetData.currentPrice
                asset.lastPriceUpdate = assetData.lastPriceUpdate
                if let interestRate = assetData.interestRate {
                    asset.setValue(interestRate, forKey: "interestRate")
                }
                if let linkedAssets = assetData.linkedAssets {
                    asset.setValue(linkedAssets, forKey: "linkedAssets")
                }
                asset.setValue(assetData.autoFetchPriceEnabled, forKey: "autoFetchPriceEnabled")

                // Fixed deposit specific fields
                if let depositSubtype = assetData.depositSubtype {
                    asset.setValue(depositSubtype, forKey: "depositSubtype")
                }
                if let maturityDate = assetData.maturityDate {
                    asset.maturityDate = maturityDate
                }
                if let allowEarlyWithdrawal = assetData.allowEarlyWithdrawal {
                    asset.setValue(allowEarlyWithdrawal, forKey: "allowEarlyWithdrawal")
                }

                assetsDict[assetData.id] = asset
            }
            
            for institutionData in package.institutions {
                let institution = Institution(context: context)
                institution.id = institutionData.id
                institution.name = institutionData.name
                institution.createdAt = institutionData.createdAt
                institutionsDict[institutionData.id] = institution
            }
            
            for portfolioData in package.portfolios {
                let portfolio = Portfolio(context: context)
                portfolio.id = portfolioData.id
                portfolio.name = portfolioData.name
                portfolio.createdAt = portfolioData.createdAt
                portfolio.updatedAt = portfolioData.updatedAt
                portfolio.mainCurrency = portfolioData.mainCurrency
                portfolio.totalValue = portfolioData.totalValue
                portfolio.enforcesCashDisciplineEnabled = portfolioData.enforcesCashDiscipline
                portfolio.ownerID = portfolioData.ownerID
                portfoliosDict[portfolioData.id] = portfolio
            }
            
            for holdingData in package.holdings {
                let holding = Holding(context: context)
                holding.id = holdingData.id
                holding.quantity = holdingData.quantity
                holding.averageCostBasis = holdingData.averageCostBasis
                holding.totalDividends = holdingData.totalDividends
                holding.realizedGainLoss = holdingData.realizedGainLoss
                holding.updatedAt = holdingData.updatedAt
                if let cashValue = holdingData.cashValue {
                    holding.setValue(cashValue, forKey: "cashValue")
                }
                if let portfolioID = holdingData.portfolioID {
                    holding.portfolio = portfoliosDict[portfolioID]
                }
                if let assetID = holdingData.assetID {
                    holding.asset = assetsDict[assetID]
                }
                if let institutionID = holdingData.institutionID {
                    holding.institution = institutionsDict[institutionID]
                }
            }

            for cashData in package.portfolioInstitutionCurrencyCash {
                let cashRecord = PortfolioInstitutionCurrencyCash(context: context)
                cashRecord.id = cashData.id
                cashRecord.currency = cashData.currency
                cashRecord.amount = cashData.amount
                cashRecord.createdAt = cashData.createdAt
                cashRecord.updatedAt = cashData.updatedAt
                cashRecord.portfolio = portfoliosDict[cashData.portfolioID]
                cashRecord.institution = institutionsDict[cashData.institutionID]
            }

            for insuranceData in package.insurances {
                guard let asset = assetsDict[insuranceData.assetID] else { continue }
                let insurance = NSEntityDescription.insertNewObject(forEntityName: "Insurance", into: context)
                insurance.setValue(insuranceData.id, forKey: "id")
                insurance.setValue(insuranceData.insuranceType, forKey: "insuranceType")
                insurance.setValue(insuranceData.policyholder, forKey: "policyholder")
                insurance.setValue(insuranceData.insuredPerson, forKey: "insuredPerson")
                insurance.setValue(insuranceData.contactNumber, forKey: "contactNumber")
                insurance.setValue(insuranceData.basicInsuredAmount, forKey: "basicInsuredAmount")
                insurance.setValue(insuranceData.additionalPaymentAmount, forKey: "additionalPaymentAmount")
                insurance.setValue(insuranceData.deathBenefit, forKey: "deathBenefit")
                insurance.setValue(insuranceData.isParticipating, forKey: "isParticipating")
                insurance.setValue(insuranceData.hasSupplementaryInsurance, forKey: "hasSupplementaryInsurance")
                insurance.setValue(insuranceData.premiumPaymentTerm, forKey: "premiumPaymentTerm")
                insurance.setValue(insuranceData.premiumPaymentStatus, forKey: "premiumPaymentStatus")
                insurance.setValue(insuranceData.premiumPaymentType, forKey: "premiumPaymentType")
                insurance.setValue(insuranceData.singlePremium, forKey: "singlePremium")
                insurance.setValue(insuranceData.firstDiscountedPremium ?? 0, forKey: "firstDiscountedPremium")
                insurance.setValue(insuranceData.totalPremium, forKey: "totalPremium")
                insurance.setValue(insuranceData.coverageExpirationDate, forKey: "coverageExpirationDate")
                insurance.setValue(insuranceData.maturityBenefitRedemptionDate, forKey: "maturityBenefitRedemptionDate")
                insurance.setValue(insuranceData.estimatedMaturityBenefit, forKey: "estimatedMaturityBenefit")
                insurance.setValue(insuranceData.canWithdrawPremiums, forKey: "canWithdrawPremiums")
                insurance.setValue(insuranceData.maxWithdrawalPercentage, forKey: "maxWithdrawalPercentage")
                insurance.setValue(insuranceData.createdAt, forKey: "createdAt")
                insurance.setValue(asset, forKey: "asset")

                for beneficiaryData in insuranceData.beneficiaries {
                    let beneficiary = NSEntityDescription.insertNewObject(forEntityName: "Beneficiary", into: context)
                    beneficiary.setValue(beneficiaryData.id, forKey: "id")
                    beneficiary.setValue(beneficiaryData.name, forKey: "name")
                    beneficiary.setValue(beneficiaryData.percentage, forKey: "percentage")
                    beneficiary.setValue(beneficiaryData.createdAt, forKey: "createdAt")
                    beneficiary.setValue(insurance, forKey: "insurance")
                }
            }

            for transactionData in package.transactions {
                let transaction = Transaction(context: context)
                transaction.id = transactionData.id
                transaction.type = transactionData.type
                transaction.transactionDate = transactionData.transactionDate
                transaction.amount = transactionData.amount
                transaction.quantity = transactionData.quantity
                transaction.price = transactionData.price
                transaction.fees = transactionData.fees
                transaction.tax = transactionData.tax
                transaction.currency = transactionData.currency
                transaction.tradingInstitution = transactionData.tradingInstitution
                transaction.transactionCode = transactionData.transactionCode
                transaction.notes = transactionData.notes
                transaction.createdAt = transactionData.createdAt
                transaction.maturityDate = transactionData.maturityDate
                transaction.setValue(transactionData.paymentInstitutionName, forKey: "paymentInstitutionName")
                transaction.setValue(transactionData.paymentDeducted, forKey: "paymentDeducted")
                transaction.setValue(transactionData.paymentDeductedAmount, forKey: "paymentDeductedAmount")
                transaction.realizedGainAmount = transactionData.realizedGain
                transaction.autoFetchPrice = transactionData.autoFetchPrice
                transaction.setValue(transactionData.interestRate, forKey: "interestRate")
                transaction.setValue(transactionData.linkedInsuranceAssetID, forKey: "linkedInsuranceAssetID")
                transaction.setValue(transactionData.linkedTransactionID, forKey: "linkedTransactionID")
                if let portfolioID = transactionData.portfolioID {
                    transaction.portfolio = portfoliosDict[portfolioID]
                }
                if let assetID = transactionData.assetID {
                    transaction.asset = assetsDict[assetID]
                }
                if let institutionID = transactionData.institutionID {
                    transaction.institution = institutionsDict[institutionID]
                }

                if transactionData.interestRate == 0,
                   let asset = transaction.asset,
                   asset.assetType == AssetType.deposit.rawValue,
                   let assetRate = asset.value(forKey: "interestRate") as? Double,
                   assetRate != 0 {
                    transaction.setValue(assetRate, forKey: "interestRate")
                }
            }

            for portfolio in portfoliosDict.values {
                portfolio.cashBalance = portfolio.getTotalCashBalanceInMainCurrency()
            }

            try context.save()
        }
    }
    
    private func clearExistingData(in context: NSManagedObjectContext) throws {
        let entityNames = ["Transaction", "Holding", "Insurance", "Beneficiary", "PortfolioInstitutionCurrencyCash", "Portfolio", "Asset", "Institution"]
        for name in entityNames {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let objects = try context.fetch(fetch)
            for case let object as NSManagedObject in objects {
                context.delete(object)
            }
        }
    }
    
    private func ensureIdentifier(for object: NSManagedObject) -> Bool {
        switch object {
        case let portfolio as Portfolio:
            if portfolio.id == nil {
                portfolio.id = UUID()
                return true
            }
        case let holding as Holding:
            if holding.id == nil {
                holding.id = UUID()
                return true
            }
        case let asset as Asset:
            if asset.id == nil {
                asset.id = UUID()
                return true
            }
        case let institution as Institution:
            if institution.id == nil {
                institution.id = UUID()
                return true
            }
        case let transaction as Transaction:
            if transaction.id == nil {
                transaction.id = UUID()
                return true
            }
        default:
            break
        }
        return false
    }
    
    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
