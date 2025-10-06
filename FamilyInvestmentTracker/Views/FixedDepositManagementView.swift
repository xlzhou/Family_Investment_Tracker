import SwiftUI
import CoreData

struct FixedDepositManagementView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext

    @State private var activeDeposits: [Asset] = []
    @State private var maturedDeposits: [Asset] = []
    @State private var showingAddFixedDeposit = false
    @State private var selectedDeposit: Asset?
    @State private var showingWithdrawalView = false

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    var body: some View {
        NavigationView {
            List {
                if !activeDeposits.isEmpty {
                    Section(header: Text("Active Fixed Deposits")) {
                        ForEach(activeDeposits, id: \.objectID) { deposit in
                            FixedDepositRowView(
                                deposit: deposit,
                                portfolio: portfolio,
                                onWithdraw: {
                                    selectedDeposit = deposit
                                    showingWithdrawalView = true
                                }
                            )
                        }
                    }
                }

                if !maturedDeposits.isEmpty {
                    Section(header: Text("Matured Fixed Deposits")) {
                        ForEach(maturedDeposits, id: \.objectID) { deposit in
                            FixedDepositRowView(
                                deposit: deposit,
                                portfolio: portfolio,
                                onWithdraw: {
                                    selectedDeposit = deposit
                                    showingWithdrawalView = true
                                }
                            )
                        }
                    }
                }

                if activeDeposits.isEmpty && maturedDeposits.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("No Fixed Deposits")
                                .font(.title2)
                                .fontWeight(.medium)

                            Text("Create your first fixed deposit to start earning guaranteed returns.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
            .navigationTitle("Fixed Deposits")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddFixedDeposit = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddFixedDeposit) {
                AddFixedDepositView(portfolio: portfolio)
            }
            .sheet(isPresented: $showingWithdrawalView) {
                if let deposit = selectedDeposit {
                    FixedDepositWithdrawalView(
                        deposit: deposit,
                        portfolio: portfolio
                    )
                }
            }
            .onAppear {
                loadFixedDeposits()
            }
            .onChange(of: showingAddFixedDeposit) { _, newValue in
                if !newValue {
                    loadFixedDeposits()
                }
            }
            .onChange(of: showingWithdrawalView) { _, newValue in
                if !newValue {
                    loadFixedDeposits()
                }
            }
        }
    }

    private func loadFixedDeposits() {
        activeDeposits = FixedDepositService.shared.getActiveFixedDeposits(for: portfolio, context: viewContext)
        maturedDeposits = FixedDepositService.shared.getMaturedFixedDeposits(for: portfolio, context: viewContext)
    }
}

struct FixedDepositRowView: View {
    let deposit: Asset
    let portfolio: Portfolio
    let onWithdraw: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
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
            return ("Matured", .orange)
        } else if let days = daysUntilMaturity {
            if days <= 30 {
                return ("\(days) days left", .orange)
            } else {
                return ("\(days) days left", .blue)
            }
        } else {
            return ("Active", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deposit.name ?? "Fixed Deposit")
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
                Label("\(String(format: "%.2f", interestRate))% p.a.", systemImage: "percent")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let maturityDate = deposit.maturityDate {
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
                            Text(isMatured ? "Withdraw" : "Early Withdraw")
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
    }
}

struct FixedDepositWithdrawalView: View {
    let deposit: Asset
    let portfolio: Portfolio

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
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
                Section(header: Text("Deposit Information")) {
                    HStack {
                        Text("Deposit Name")
                        Spacer()
                        Text(deposit.name ?? "Fixed Deposit")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Current Value")
                        Spacer()
                        Text(currencyService.formatAmountWithFullCurrency(maxWithdrawalAmount, in: depositCurrency))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(isMatured ? "Matured" : "Active")
                            .foregroundColor(isMatured ? .orange : .green)
                    }
                }

                Section(header: Text("Withdrawal Details")) {
                    HStack {
                        Text("Withdrawal Amount")
                        Spacer()
                        TextField("0.00", text: $withdrawalAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if !isMatured {
                        HStack {
                            Text("Accrued Interest")
                            Spacer()
                            TextField("0.00", text: $accruedInterest)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Institution Penalty")
                            Spacer()
                            TextField("0.00", text: $institutionPenalty)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if !isMatured {
                    Section(footer: Text("Early withdrawal may incur penalties. Please confirm the accrued interest and penalty amounts with your institution.")) {
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
            .navigationTitle(isMatured ? "Withdraw" : "Early Withdrawal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Withdraw") {
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
            errorMessage = "Invalid withdrawal amount"
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
            errorMessage = "Failed to process withdrawal: \(error.localizedDescription)"
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
