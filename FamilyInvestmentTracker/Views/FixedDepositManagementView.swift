import SwiftUI
import CoreData

struct FixedDepositManagementView: View {
    @ObservedObject var portfolio: Portfolio

    var body: some View {
        CashOverviewView(portfolio: portfolio, initialTab: .fixedDeposits)
    }
}

struct FixedDepositRowView: View {
    let deposit: Asset
    let portfolio: Portfolio
    let onWithdraw: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var currencyService = CurrencyService.shared

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var currentValue: Double {
        // Fixed deposits don't use holdings - currentPrice represents the deposit amount
        return deposit.currentPrice
    }

    private var depositCurrency: Currency {
        // Get the currency from the deposit's transactions
        let transactions = (deposit.transactions?.allObjects as? [Transaction]) ?? []

        // Debug logging
        //print("🔍 UI Debug: Found \(transactions.count) transactions for deposit: \(deposit.name ?? "Unknown")")
        if let firstTransaction = transactions.first {
            let detectedCurrency = Currency(rawValue: firstTransaction.currency ?? "USD") ?? .usd
            //print("🔍 UI Debug: Using currency from first transaction: \(detectedCurrency.rawValue)")
            return detectedCurrency
        }

        //print("🔍 UI Debug: No transactions found, falling back to main currency: \(mainCurrency.rawValue)")
        return mainCurrency
    }

    private var interestRate: Double {
        return (deposit.value(forKey: "interestRate") as? Double) ?? 0.0
    }

    private var isMatured: Bool {
        return deposit.isMatured
    }

    private var daysUntilMaturity: Int? {
        return deposit.daysUntilMaturity
    }

    private var maturityStatus: (text: String, color: Color) {
        if isMatured {
            return (localizationManager.localizedString(for: "fixedDepositManagement.matured"), .orange)
        } else if let days = daysUntilMaturity {
            if days <= 30 {
                return (String(format: localizationManager.localizedString(for: "fixedDepositManagement.daysLeft"), days), .orange)
            } else {
                return (String(format: localizationManager.localizedString(for: "fixedDepositManagement.daysLeft"), days), .blue)
            }
        } else {
            return (localizationManager.localizedString(for: "fixedDepositManagement.active"), .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deposit.name ?? localizationManager.localizedString(for: "fixedDepositManagement.fixedDeposit"))
                        .font(.headline)

                    if let symbol = deposit.symbol {
                        Text(symbol)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(currencyService.formatAmountWithFullCurrency(currentValue, in: depositCurrency))
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(maturityStatus.text)
                        .font(.caption)
                        .foregroundColor(maturityStatus.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(maturityStatus.color.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            HStack {
                Label("\(String(format: "%.2f", interestRate))% \(localizationManager.localizedString(for: "fixedDepositManagement.perAnnum"))", systemImage: "percent")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if isMatured {
                    Label {
                        Text(localizationManager.localizedString(for: "fixedDepositManagement.matured"))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                } else if let maturityDate = deposit.maturityDate {
                    Label {
                        Text(maturityDate, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if isMatured || deposit.allowEarlyWithdrawal {
                HStack {
                    Spacer()
                    Button(action: onWithdraw) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text(isMatured ? localizationManager.localizedString(for: "fixedDepositManagement.withdraw") : localizationManager.localizedString(for: "fixedDepositManagement.earlyWithdraw"))
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isMatured ? Color.green : Color.orange)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
#if DEBUG
            debugPrintMaturity()
#endif
        }
    }
}

#if DEBUG
private extension FixedDepositRowView {
    func debugPrintMaturity() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let name = deposit.name ?? deposit.symbol ?? "Fixed Deposit"
        if let maturityDate = deposit.maturityDate {
            let maturityString = formatter.string(from: maturityDate)
            let daysLeft = deposit.daysUntilMaturity ?? -1
            print("🔎 FixedDepositRowView: \(name) maturity=\(maturityString) daysLeft=\(daysLeft)")
        } else {
            print("🔎 FixedDepositRowView: \(name) has no maturity date")
        }
    }
}
#endif

struct FixedDepositWithdrawalView: View {
    let deposit: Asset
    let portfolio: Portfolio

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var currencyService = CurrencyService.shared

    @State private var withdrawalAmount = ""
    @State private var accruedInterest = ""
    @State private var institutionPenalty = ""
    @State private var errorMessage = ""

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var depositCurrency: Currency {
        // Get the currency from the deposit's transactions
        let transactions = (deposit.transactions?.allObjects as? [Transaction]) ?? []

        // Debug logging
        print("🔍 UI Debug (Withdrawal): Found \(transactions.count) transactions for deposit: \(deposit.name ?? "Unknown")")
        for (index, transaction) in transactions.enumerated() {
            print("🔍 UI Debug (Withdrawal): Transaction \(index + 1): Amount=\(transaction.amount), Currency='\(transaction.currency ?? "nil")', Type=\(transaction.type ?? "nil")")
        }

        if let firstTransaction = transactions.first {
            let detectedCurrency = Currency(rawValue: firstTransaction.currency ?? "USD") ?? .usd
            print("🔍 UI Debug (Withdrawal): Using currency from first transaction: \(detectedCurrency.rawValue)")
            return detectedCurrency
        }

        print("🔍 UI Debug (Withdrawal): No transactions found, falling back to main currency: \(mainCurrency.rawValue)")
        return mainCurrency
    }

    private var maxWithdrawalAmount: Double {
        // Fixed deposits don't use holdings - currentPrice represents the deposit amount
        return deposit.currentPrice
    }

    private var isMatured: Bool {
        return deposit.isMatured
    }

    private var institution: Institution? {
        // Get institution from deposit's transactions instead of holdings
        let transactions = (deposit.transactions?.allObjects as? [Transaction]) ?? []
        return transactions.first?.institution
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.depositInformation"))) {
                    HStack {
                        Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.depositName"))
                        Spacer()
                        Text(deposit.name ?? localizationManager.localizedString(for: "fixedDepositManagement.fixedDeposit"))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.currentValue"))
                        Spacer()
                        Text(currencyService.formatAmountWithFullCurrency(maxWithdrawalAmount, in: depositCurrency))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.status"))
                        Spacer()
                        Text(isMatured ? localizationManager.localizedString(for: "fixedDepositManagement.matured") : localizationManager.localizedString(for: "fixedDepositManagement.active"))
                            .foregroundColor(isMatured ? .orange : .green)
                    }
                }

                Section(header: Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.withdrawalDetails"))) {
                    HStack {
                        Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.withdrawalAmount"))
                        Spacer()
                        TextField("0.00", text: $withdrawalAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if !isMatured {
                        HStack {
                            Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.accruedInterest"))
                            Spacer()
                            TextField("0.00", text: $accruedInterest)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.institutionPenalty"))
                            Spacer()
                            TextField("0.00", text: $institutionPenalty)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if !isMatured {
                    Section(footer: Text(localizationManager.localizedString(for: "fixedDepositWithdrawal.earlyWithdrawalWarning"))) {
                        EmptyView()
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(isMatured ? localizationManager.localizedString(for: "fixedDepositWithdrawal.navigation.withdraw") : localizationManager.localizedString(for: "fixedDepositWithdrawal.navigation.earlyWithdrawal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "fixedDepositWithdrawal.navigation.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "fixedDepositWithdrawal.navigation.withdraw")) {
                        processWithdrawal()
                    }
                    .disabled(!isValidInput)
                }
            }
            .onAppear {
                withdrawalAmount = String(maxWithdrawalAmount)
            }
        }
    }

    private var isValidInput: Bool {
        guard let amount = Double(withdrawalAmount),
              amount > 0,
              amount <= maxWithdrawalAmount,
              institution != nil else {
            return false
        }

        if !isMatured {
            guard let _ = Double(accruedInterest),
                  let _ = Double(institutionPenalty) else {
                return false
            }
        }

        return true
    }

    private func processWithdrawal() {
        guard let amount = Double(withdrawalAmount),
              let institution = institution else {
            errorMessage = localizationManager.localizedString(for: "fixedDepositWithdrawal.error.invalidAmount")
            return
        }

        let accruedInterestValue = Double(accruedInterest) ?? 0.0
        let penaltyValue = Double(institutionPenalty) ?? 0.0

        do {
            if isMatured {
                _ = FixedDepositService.shared.processMaturityWithdrawal(
                    from: deposit,
                    portfolio: portfolio,
                    institution: institution,
                    currency: mainCurrency,
                    context: viewContext
                )
            } else {
                _ = FixedDepositService.shared.processEarlyWithdrawal(
                    from: deposit,
                    amount: amount,
                    accruedInterest: accruedInterestValue,
                    institutionPenalty: penaltyValue,
                    portfolio: portfolio,
                    institution: institution,
                    currency: mainCurrency,
                    context: viewContext
                )
            }

            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = String(format: localizationManager.localizedString(for: "fixedDepositWithdrawal.error.processingFailed"), error.localizedDescription)
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "Test Portfolio"
    portfolio.mainCurrency = "USD"

    return FixedDepositManagementView(portfolio: portfolio)
        .environment(\.managedObjectContext, context)
}
