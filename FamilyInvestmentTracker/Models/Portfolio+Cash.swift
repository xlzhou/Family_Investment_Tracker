import Foundation
import CoreData

extension Portfolio {
    // Safe access to cashBalance using KVC, in case codegen hasn't updated yet
    var cashBalanceSafe: Double {
        get { (self.value(forKey: "cashBalance") as? Double) ?? 0.0 }
        set { self.setValue(newValue, forKey: "cashBalance") }
    }

    func addToCash(_ delta: Double) {
        cashBalanceSafe = cashBalanceSafe + delta
    }

    var enforcesCashDisciplineEnabled: Bool {
        get { (self.value(forKey: "enforcesCashDiscipline") as? Bool) ?? true }
        set { self.setValue(newValue, forKey: "enforcesCashDiscipline") }
    }

    func resolvedCashBalance(tolerance: Double = 0.01) -> Double {
        let currencyBalances = (currencyCashBalances?.allObjects as? [PortfolioInstitutionCurrencyCash]) ?? []

        if !currencyBalances.isEmpty {
            return getTotalCashBalanceInMainCurrency()
        }

        return cashBalanceSafe
    }

    // MARK: - Enhanced Cash Balance Methods

    /// Total cash balance including both available cash and fixed deposits
    var totalCashBalance: Double {
        return CashBalanceService.shared.getTotalCashBalance(for: self)
    }

    /// Available cash balance (demand deposits + savings accounts)
    var availableCashBalance: Double {
        return CashBalanceService.shared.getAvailableCashBalance(for: self)
    }

    /// Fixed deposit balance (locked funds)
    var fixedDepositBalance: Double {
        return CashBalanceService.shared.getFixedDepositBalance(for: self)
    }

    /// Check if there's sufficient available cash for a transaction
    func hasSufficientAvailableCash(amount: Double, currency: Currency) -> Bool {
        return CashBalanceService.shared.hasSufficientAvailableCash(for: self, amount: amount, currency: currency)
    }

    /// Check if there's sufficient total cash (including fixed deposits) for a transaction
    func hasSufficientTotalCash(amount: Double, currency: Currency) -> Bool {
        return CashBalanceService.shared.hasSufficientTotalCash(for: self, amount: amount, currency: currency)
    }
}
