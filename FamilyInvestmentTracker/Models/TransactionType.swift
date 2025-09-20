import Foundation

enum TransactionType: String, CaseIterable {
    case buy = "Buy"
    case sell = "Sell"
    case dividend = "Dividend"
    case interest = "Interest"
    case deposit = "Deposit"
    case insurance = "Insurance"
    
    var displayName: String {
        return self.rawValue
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
        return self.rawValue
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
