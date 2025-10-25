import Foundation

enum TransactionType: String, CaseIterable {
    case buy = "Buy"
    case sell = "Sell"
    case dividend = "Dividend"
    case interest = "Interest"
    case deposit = "Deposit"
    case insurance = "Insurance"
    case depositWithdrawal = "DepositWithdrawal"

    var displayName: String {
        LocalizationManager.shared.localizedString(for: localizationKey, fallback: rawValue)
    }

    private var localizationKey: String {
        switch self {
        case .buy: return "transaction.type.buy"
        case .sell: return "transaction.type.sell"
        case .dividend: return "transaction.type.dividend"
        case .interest: return "transaction.type.interest"
        case .deposit: return "transaction.type.deposit"
        case .insurance: return "transaction.type.insurance"
        case .depositWithdrawal: return "transaction.type.depositWithdrawal"
        }
    }
}

enum AssetType: String, CaseIterable {
    case stock = "Stock"
    case etf = "ETF"
    case bond = "Bond"
    case mutualFund = "Mutual Fund"
    case deposit = "Deposit"
    case cryptocurrency = "Cryptocurrency"
    case preciousMetal = "Precious Metal"
    case insurance = "Insurance"
    case structuredProduct = "Structured Product"
    case other = "Other"
    
    var displayName: String {
        LocalizationManager.shared.localizedString(for: localizationKey, fallback: rawValue)
    }

    private var localizationKey: String {
        switch self {
        case .stock: return "asset.type.stock"
        case .etf: return "asset.type.etf"
        case .bond: return "asset.type.bond"
        case .mutualFund: return "asset.type.mutualFund"
        case .deposit: return "asset.type.deposit"
        case .cryptocurrency: return "asset.type.cryptocurrency"
        case .preciousMetal: return "asset.type.preciousMetal"
        case .insurance: return "asset.type.insurance"
        case .structuredProduct: return "asset.type.structuredProduct"
        case .other: return "asset.type.other"
        }
    }
}

enum Currency: String, CaseIterable {
    case usd = "USD"
    case cny = "CNY"
    case ntd = "TWD"
    case hkd = "HKD"
    case jpy = "JPY"
    case eur = "EUR"
    
    var displayName: String {
        return "\(self.rawValue) \(self.symbol)"
    }
    
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .cny: return "¥"
        case .ntd: return "$"
        case .hkd: return "$"
        case .jpy: return "¥"
        case .eur: return "€"
        }
    }
    
    var code: String {
        return self.rawValue
    }
}
