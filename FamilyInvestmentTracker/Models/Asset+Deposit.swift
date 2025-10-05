import Foundation
import CoreData

extension Asset {

    // MARK: - Deposit Subtype

    enum DepositSubtype: String, CaseIterable {
        case demand = "demand"
        case fixed = "fixed"
        case savings = "savings"

        var displayName: String {
            switch self {
            case .demand: return "Demand Deposit"
            case .fixed: return "Fixed Deposit"
            case .savings: return "Savings Account"
            }
        }

        var isLiquid: Bool {
            switch self {
            case .demand: return true
            case .fixed: return false
            case .savings: return true
            }
        }
    }

    var depositSubtypeEnum: DepositSubtype {
        get {
            guard let subtypeString = depositSubtype,
                  let subtype = DepositSubtype(rawValue: subtypeString) else {
                return .demand
            }
            return subtype
        }
        set {
            depositSubtype = newValue.rawValue
        }
    }

    var isFixedDeposit: Bool {
        return depositSubtypeEnum == .fixed
    }

    var isDemandDeposit: Bool {
        return depositSubtypeEnum == .demand
    }

    var isSavingsAccount: Bool {
        return depositSubtypeEnum == .savings
    }

    // MARK: - Fixed Deposit Properties

    var daysUntilMaturity: Int? {
        guard let maturityDate = maturityDate else { return nil }
        let calendar = Calendar.current
        let today = Date()
        let components = calendar.dateComponents([.day], from: today, to: maturityDate)
        return components.day
    }

    var isMatured: Bool {
        guard let maturityDate = maturityDate else { return false }
        return Date() >= maturityDate
    }

    var isActiveFixedDeposit: Bool {
        return isFixedDeposit && !isMatured
    }

    // MARK: - Asset Naming Helpers

    static func generateFixedDepositName(termMonths: Int, institution: String? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"
        let year = dateFormatter.string(from: Date())

        let termString: String
        if termMonths >= 12 {
            let years = termMonths / 12
            termString = "\(years)Y"
        } else {
            termString = "\(termMonths)M"
        }

        let institutionPart = institution?.replacingOccurrences(of: " ", with: "") ?? ""

        return "FD-\(year)-\(termString)-\(institutionPart)"
    }

    static func generateFixedDepositDisplayName(termMonths: Int, institution: String? = nil) -> String {
        let termString: String
        if termMonths >= 12 {
            let years = termMonths / 12
            termString = "\(years)-Year"
        } else {
            termString = "\(termMonths)-Month"
        }

        let institutionPart = institution != nil ? " - \(institution!)" : ""

        return "\(termString) Fixed Deposit\(institutionPart)"
    }

    // MARK: - Validation

    func canWithdrawEarly() -> Bool {
        guard isFixedDeposit else { return true }
        return allowEarlyWithdrawal
    }

    func validateForWithdrawal(amount: Double) -> Bool {
        guard isFixedDeposit else { return true }

        if isMatured {
            return true
        }

        return canWithdrawEarly()
    }
}