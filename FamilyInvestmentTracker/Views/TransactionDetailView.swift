import SwiftUI
import Foundation
import CoreData

struct TransactionDetailView: View {
    @ObservedObject var transaction: Transaction
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingPaymentManagement = false
    private let currencyService = CurrencyService.shared
    
    private var currency: Currency {
        Currency(rawValue: transaction.currency ?? "USD") ?? .usd
    }

    private var netValue: Double {
        return transaction.amount - transaction.fees - transaction.tax
    }

    private var transactionTypeEnum: TransactionType? {
        TransactionType(rawValue: transaction.type ?? "")
    }

    private var isInsurance: Bool {
        transaction.type == TransactionType.insurance.rawValue
    }

    private var insurance: NSManagedObject? {
        transaction.asset?.value(forKey: "insurance") as? NSManagedObject
    }

    private var depositInterestRateText: String? {
        guard transactionTypeEnum == .deposit else { return nil }
        let rate = (transaction.value(forKey: "interestRate") as? Double) ?? 0
        return Formatters.percent(rate, fractionDigits: 2)
    }

    private var isStructuredProduct: Bool {
        transaction.asset?.assetType == AssetType.structuredProduct.rawValue
    }

    private var structuredProductInterestRateText: String {
        let rate = (transaction.asset?.value(forKey: "interestRate") as? Double) ?? 0
        return Formatters.percent(rate, fractionDigits: 2)
    }

    private var structuredProductLinkedAssets: String {
        (transaction.asset?.value(forKey: "linkedAssets") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var settlementAmount: Double {
        switch transactionTypeEnum {
        case .some(.buy):
            return transaction.amount + transaction.fees + transaction.tax
        case .some(.sell), .some(.deposit), .some(.dividend), .some(.interest), .some(.insurance):
            return transaction.amount - transaction.fees - transaction.tax
        case .none:
            return transaction.amount
        }
    }

    private var totalPaidPremium: Double {
        guard isInsurance else { return 0 }

        return insurancePaymentDeposits.reduce(0) { runningTotal, txn in
            let depositCurrency = Currency(rawValue: txn.currency ?? currency.rawValue) ?? currency
            let converted = currencyService.convertAmount(abs(txn.amount), from: depositCurrency, to: currency)
            return runningTotal + converted
        }
    }

    private var insurancePaymentDeposits: [Transaction] {
        guard let portfolio = transaction.portfolio,
              let insuranceAsset = transaction.asset else { return [] }

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        return transactions.filter { txn in
            guard txn.portfolio?.objectID == portfolio.objectID else { return false }
            guard txn.type == TransactionType.deposit.rawValue else { return false }
            return isInsurancePaymentTransaction(txn, asset: insuranceAsset, originalTransaction: transaction)
        }
    }

    private func isInsurancePaymentTransaction(_ transaction: Transaction,
                                               asset: Asset,
                                               originalTransaction: Transaction? = nil) -> Bool {
        guard let notesLowercased = transaction.notes?.lowercased() else { return false }

        if let original = originalTransaction,
           let identifier = CashDisciplineService.companionNoteIdentifier(for: original)?.lowercased(),
           notesLowercased.hasPrefix(identifier) {
            return true
        }

        if notesLowercased.contains("premium payment") {
            return true
        }

        if let symbol = asset.symbol?.lowercased(), !symbol.isEmpty, notesLowercased.contains(symbol) {
            return true
        }

        if let name = asset.name?.lowercased(), !name.isEmpty, notesLowercased.contains(name) {
            return true
        }
        return false
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Overview")) {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(transaction.type ?? "-")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(transaction.transactionDate ?? Date(), style: .date)
                            .foregroundColor(.secondary)
                    }
                    if let maturity = transaction.maturityDate {
                        HStack {
                            Text("Maturity Date")
                            Spacer()
                            Text(maturity, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                    if isInsurance {
                        HStack {
                            Text("Paid Premium")
                            Spacer()
                            Text(Formatters.currency(totalPaidPremium, symbol: currency.symbol))
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                        }
                    } else {
                        HStack {
                            Text("Trade Amount")
                            Spacer()
                            Text(Formatters.currency(transaction.amount, symbol: currency.symbol))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Settlement Amount")
                            Spacer()
                            Text(Formatters.currency(settlementAmount, symbol: currency.symbol))
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                        }
                    }
                    if let paymentInstitution = transaction.value(forKey: "paymentInstitutionName") as? String, !paymentInstitution.isEmpty {
                        HStack {
                            Text("Payment Institution")
                            Spacer()
                            Text(paymentInstitution)
                                .foregroundColor(.secondary)
                        }
                    }
                    if isInsurance {
                        HStack {
                            Text("Payment Deducted")
                            Spacer()
                            let deducted = (transaction.value(forKey: "paymentDeducted") as? Bool) ?? false
                            Text(deducted ? "Yes" : "No")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                let isDividend = transactionTypeEnum == .dividend
                Section(header: Text(isDividend ? "Dividend Source" : "Asset")) {
                    HStack {
                        Text("Symbol")
                        Spacer()
                        Text(transaction.asset?.symbol ?? "-")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(transaction.asset?.name ?? "-")
                            .foregroundColor(.secondary)
                    }
                    if transactionTypeEnum == .deposit {
                        HStack {
                            Text("Interest Rate")
                            Spacer()
                            Text(depositInterestRateText ?? "0%")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Price")
                            Spacer()
                            Text(Formatters.currency(transaction.price, symbol: currency.symbol))
                                .foregroundColor(.secondary)
                        }
                    } else if isStructuredProduct {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text(Formatters.decimal(transaction.quantity, fractionDigits: 5))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Price per Share")
                            Spacer()
                            Text(Formatters.currency(transaction.price, symbol: currency.symbol, fractionDigits: 6))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Investment Amount")
                            Spacer()
                            Text(Formatters.currency(transaction.quantity * transaction.price, symbol: currency.symbol))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Interest Rate")
                            Spacer()
                            Text(structuredProductInterestRateText)
                                .foregroundColor(.secondary)
                        }
                        if !structuredProductLinkedAssets.isEmpty {
                            HStack {
                                Text("Linked Assets")
                                Spacer()
                                Text(structuredProductLinkedAssets)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if !isDividend {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text(Formatters.decimal(transaction.quantity, fractionDigits: 5))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text(isInsurance ? "Cash Value" : "Price")
                            Spacer()
                            Text(Formatters.currency(transaction.price, symbol: currency.symbol))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Costs")) {
                    HStack {
                        Text("Fees")
                        Spacer()
                        Text(Formatters.currency(transaction.fees, symbol: currency.symbol))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(Formatters.currency(transaction.tax, symbol: currency.symbol))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Institution")
                        Spacer()
                        Text(transaction.tradingInstitution ?? "-")
                            .foregroundColor(.secondary)
                    }
                    if transaction.type == TransactionType.sell.rawValue {
                        HStack {
                            Text("Realized P&L")
                            Spacer()
                            let realized = transaction.realizedGainAmount
                            Text(Formatters.signedCurrency(realized, symbol: currency.symbol))
                                .foregroundColor(realized >= 0 ? .green : .red)
                        }
                    }
                }

                if isInsurance {
                    insuranceDetailsSection
                    insuranceFinancialSection
                    insurancePremiumSection
                    insuranceCoverageSection
                    insuranceBeneficiariesSection
                }

                if let notes = transaction.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }

                if isInsurance {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button("Payments") {
                                showingPaymentManagement = true
                            }

                            Button("Edit") {
                                showingEdit = true
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            showingEdit = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddTransactionView(portfolio: portfolio, transactionToEdit: transaction)
                .environment(\.managedObjectContext, viewContext)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingPaymentManagement) {
            if let asset = transaction.asset {
                InsurancePaymentManagementView(portfolio: portfolio, insuranceAsset: asset)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    @ViewBuilder
    private var insuranceDetailsSection: some View {
        Section(header: Text("Insurance Details")) {
            HStack {
                Text("Policy Symbol")
                Spacer()
                Text(transaction.asset?.symbol ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policy Type")
                Spacer()
                Text(insurance?.value(forKey: "insuranceType") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Policyholder")
                Spacer()
                Text(insurance?.value(forKey: "policyholder") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Insured Person")
                Spacer()
                Text(insurance?.value(forKey: "insuredPerson") as? String ?? "-")
                    .foregroundColor(.secondary)
            }
            if let phone = insurance?.value(forKey: "contactNumber") as? String, !phone.isEmpty {
                HStack {
                    Text("Contact Number")
                    Spacer()
                    Text(phone)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceFinancialSection: some View {
        Section(header: Text("Financial Details")) {
            valueRow(label: "Basic Insured Amount", amount: insurance?.value(forKey: "basicInsuredAmount") as? Double)
            valueRow(label: "Additional Payment", amount: insurance?.value(forKey: "additionalPaymentAmount") as? Double)
            valueRow(label: "Death Benefit", amount: insurance?.value(forKey: "deathBenefit") as? Double)
        }
    }

    @ViewBuilder
    private var insurancePremiumSection: some View {
        Section(header: Text("Premium Details")) {
            let paymentType = insurance?.value(forKey: "premiumPaymentType") as? String ?? "-"
            let paymentStatus = insurance?.value(forKey: "premiumPaymentStatus") as? String ?? "-"
            HStack {
                Text("Payment Type")
                Spacer()
                Text(paymentType)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Payment Status")
                Spacer()
                Text(paymentStatus)
                    .foregroundColor(.secondary)
            }
            valueRow(label: "Single Premium", amount: insurance?.value(forKey: "singlePremium") as? Double)
            if let discounted = insurance?.value(forKey: "firstDiscountedPremium") as? Double, abs(discounted) > 1e-6 {
                valueRow(label: "First Discounted Premium", amount: discounted)
            }
            valueRow(label: "Total Premium", amount: insurance?.value(forKey: "totalPremium") as? Double)
            if let term = insurance?.value(forKey: "premiumPaymentTerm") as? Int32, term > 0 {
                HStack {
                    Text("Payment Term")
                    Spacer()
                    Text("\(term) years")
                        .foregroundColor(.secondary)
                }
            }
            toggleRow(label: "Participating", value: insurance?.value(forKey: "isParticipating") as? Bool)
            toggleRow(label: "Supplementary Insurance", value: insurance?.value(forKey: "hasSupplementaryInsurance") as? Bool)
        }
    }

    @ViewBuilder
    private var insuranceCoverageSection: some View {
        Section(header: Text("Coverage & Benefits")) {
            if let expiration = insurance?.value(forKey: "coverageExpirationDate") as? Date {
                dateRow(label: "Coverage Expiration", date: expiration)
            }
            if let maturityDate = insurance?.value(forKey: "maturityBenefitRedemptionDate") as? Date {
                dateRow(label: "Maturity Benefit Date", date: maturityDate)
            }
            valueRow(label: "Estimated Maturity Benefit", amount: insurance?.value(forKey: "estimatedMaturityBenefit") as? Double)
            toggleRow(label: "Can Withdraw Premiums", value: insurance?.value(forKey: "canWithdrawPremiums") as? Bool)
            if let percentage = insurance?.value(forKey: "maxWithdrawalPercentage") as? Double, percentage > 0 {
                HStack {
                    Text("Max Withdrawal %")
                    Spacer()
                    Text("\(Formatters.decimal(percentage, fractionDigits: 1))%")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var insuranceBeneficiariesSection: some View {
        if let beneficiaries = insurance?.value(forKey: "beneficiaries") as? Set<NSManagedObject>, !beneficiaries.isEmpty {
            Section(header: Text("Beneficiaries")) {
                ForEach(Array(beneficiaries), id: \.objectID) { beneficiary in
                    HStack {
                        Text(beneficiary.value(forKey: "name") as? String ?? "-" )
                        Spacer()
                        let pct = beneficiary.value(forKey: "percentage") as? Double ?? 0
                        Text("\(Formatters.decimal(pct, fractionDigits: 1))%")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func valueRow(label: String, amount: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Formatters.currency(amount ?? 0, symbol: currency.symbol))
                .foregroundColor(.secondary)
        }
    }

    private func toggleRow(label: String, value: Bool?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text((value ?? false) ? "Yes" : "No")
                .foregroundColor(.secondary)
        }
    }

    private func dateRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(date, style: .date)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Insurance Payment Management

struct InsurancePaymentManagementView: View {
    @ObservedObject var portfolio: Portfolio
    @ObservedObject var insuranceAsset: Asset
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingPaymentEntry = false
    @State private var paymentEntryType: PaymentEntryType = .regular

    private let currencyService = CurrencyService.shared

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var paymentTransactions: [Transaction] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []

        let primaryInsuranceTransaction = transactions.first { txn in
            guard txn.portfolio?.objectID == portfolio.objectID else { return false }
            return txn.type == TransactionType.insurance.rawValue && txn.asset?.objectID == insuranceAsset.objectID
        }

        return transactions.filter { txn in
            guard txn.portfolio?.objectID == portfolio.objectID else { return false }

            let type = TransactionType(rawValue: txn.type ?? "")

            switch type {
            case .some(.insurance):
                return txn.asset?.objectID == insuranceAsset.objectID
            case .some(.deposit):
                return isInsurancePaymentTransaction(txn,
                                                    asset: insuranceAsset,
                                                    originalTransaction: primaryInsuranceTransaction)
            default:
                return false
            }
        }
        .sorted { ($0.transactionDate ?? Date.distantPast) < ($1.transactionDate ?? Date.distantPast) }
    }

    private var originalTransaction: Transaction? {
        paymentTransactions.first { $0.type == TransactionType.insurance.rawValue }
    }

    private var paymentHistory: [Transaction] {
        paymentTransactions
    }

    private var displayPaymentHistory: [Transaction] {
        paymentTransactions.filter { transaction in
            guard transaction.type == TransactionType.deposit.rawValue else { return true }
            let notes = transaction.notes ?? ""
            return !notes.hasPrefix("[CashDiscipline] Linked Transaction")
        }
    }

    private var insurance: NSManagedObject? {
        insuranceAsset.value(forKey: "insurance") as? NSManagedObject
    }

    private var singlePremium: Double {
        insurance?.value(forKey: "singlePremium") as? Double ?? 0
    }

    private var configuredFirstDiscountedPremium: Double {
        insurance?.value(forKey: "firstDiscountedPremium") as? Double ?? 0
    }

    private var totalPremium: Double {
        insurance?.value(forKey: "totalPremium") as? Double ?? 0
    }

    private var paymentTerm: Int32 {
        insurance?.value(forKey: "premiumPaymentTerm") as? Int32 ?? 0
    }

    private var paymentType: String {
        insurance?.value(forKey: "premiumPaymentType") as? String ?? "Lump Sum"
    }

    private var isInstallmentPolicy: Bool {
        paymentType.lowercased().contains("installment") && paymentTerm > 1
    }

    private var expectedInstallmentAmount: Double {
        guard isInstallmentPolicy && paymentTerm > 0 else { return totalPremium }
        return singlePremium
    }

    private var firstPaymentExpectedAmount: Double {
        if configuredFirstDiscountedPremium > 0 {
            return configuredFirstDiscountedPremium
        }
        return expectedInstallmentAmount
    }

    private var insuranceTransactionCurrency: Currency {
        Currency(rawValue: originalTransaction?.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
    }

    private var defaultFirstPaymentAmount: Double {
        if configuredFirstDiscountedPremium > 0 {
            return configuredFirstDiscountedPremium
        }

        let expected = expectedInstallmentAmount
        if expected > 0 { return expected }
        if let original = originalTransaction { return abs(original.amount) }
        return 0
    }

    private var firstPaymentDisplayAmount: Double? {
        guard let original = originalTransaction else { return nil }
        let transactionCurrency = insuranceTransactionCurrency

        if let companion = CashDisciplineService.findCompanionDeposit(for: original, in: viewContext) {
            let companionCurrency = Currency(rawValue: companion.currency ?? transactionCurrency.rawValue) ?? transactionCurrency
            let payment = abs(companion.amount)
            if companionCurrency == transactionCurrency {
                return payment
            } else {
                return currencyService.convertAmount(payment, from: companionCurrency, to: transactionCurrency)
            }
        }

        if let deductedFlag = original.value(forKey: "paymentDeducted") as? Bool,
           deductedFlag,
           let deductedPortfolioAmount = original.value(forKey: "paymentDeductedAmount") as? Double,
           deductedPortfolioAmount > 0 {
            return currencyService.convertAmount(deductedPortfolioAmount, from: portfolioCurrency, to: transactionCurrency)
        }

        let expected = defaultFirstPaymentAmount
        if expected > 0 { return expected }
        return abs(original.amount)
    }

    private var firstPaymentHasDiscount: Bool {
        guard let display = firstPaymentDisplayAmount else { return false }
        let benchmark = singlePremium > 0 ? singlePremium : expectedInstallmentAmount
        guard benchmark > 0 else { return false }

        if configuredFirstDiscountedPremium > 0 {
            return configuredFirstDiscountedPremium + 1e-6 < benchmark
        }

        return display + 1e-6 < benchmark
    }

    private var totalPaidAmount: Double {
        paymentTransactions.reduce(0) { total, transaction in
            guard transaction.type == TransactionType.deposit.rawValue else { return total }
            let depositCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
            let converted = currencyService.convertAmount(abs(transaction.amount), from: depositCurrency, to: portfolioCurrency)
            return total + converted
        }
    }

    private var remainingBalance: Double {
        max(0, totalPremium - totalPaidAmount)
    }

    private var paymentProgress: Double {
        guard totalPremium > 0 else { return 0 }
        return min(1.0, totalPaidAmount / totalPremium)
    }

    private var nextPaymentDue: Date? {
        guard isInstallmentPolicy, remainingBalance > 0 else { return nil }

        if let lastPayment = paymentHistory.last?.transactionDate {
            return Calendar.current.date(byAdding: .year, value: 1, to: lastPayment)
        }

        if let originalDate = originalTransaction?.transactionDate {
            return Calendar.current.date(byAdding: .year, value: 1, to: originalDate)
        }

        return nil
    }

    private var isFirstPaymentPending: Bool {
        paymentHistory.count <= 1
    }


    var body: some View {
        NavigationView {
            Form {
                paymentScheduleSection
                paymentHistorySection
            }
            .navigationTitle("Payment Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Payment") {
                        paymentEntryType = .regular
                        showingPaymentEntry = true
                    }
                    .disabled(remainingBalance <= 0)
                }
            }
        }
        .sheet(isPresented: $showingPaymentEntry) {
            InsurancePaymentEntryView(
                portfolio: portfolio,
                insuranceAsset: insuranceAsset,
                paymentType: paymentEntryType,
                expectedAmount: isFirstPaymentPending ? firstPaymentExpectedAmount : expectedInstallmentAmount
            )
            .environment(\.managedObjectContext, viewContext)
        }
    }

    @ViewBuilder
    private var paymentScheduleSection: some View {
        Section(header: Text("Payment Schedule")) {
            HStack {
                Text("Policy Type")
                Spacer()
                Text(paymentType)
                    .foregroundColor(.secondary)
            }

            if isInstallmentPolicy {
                HStack {
                    Text("Payment Term")
                    Spacer()
                    Text("\(paymentTerm) years")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Annual Premium")
                    Spacer()
                    Text(Formatters.currency(expectedInstallmentAmount, symbol: portfolioCurrency.symbol))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Total Premium")
                Spacer()
                Text(Formatters.currency(totalPremium, symbol: portfolioCurrency.symbol))
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Payment Progress")
                    Spacer()
                    Text("\(Int(paymentProgress * 100))%")
                        .foregroundColor(.secondary)
                }

                ProgressView(value: paymentProgress)
                    .progressViewStyle(LinearProgressViewStyle())

                HStack {
                    Text("Paid: \(Formatters.currency(totalPaidAmount, symbol: portfolioCurrency.symbol))")
                        .font(.caption)
                        .foregroundColor(.green)

                    Spacer()

                    Text("Remaining: \(Formatters.currency(remainingBalance, symbol: portfolioCurrency.symbol))")
                        .font(.caption)
                        .foregroundColor(remainingBalance > 0 ? .orange : .green)
                }
            }

            if let nextDue = nextPaymentDue {
                HStack {
                    Text("Next Payment Due")
                    Spacer()
                    Text(nextDue, style: .date)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
            }
        }
    }

    @ViewBuilder
    private var paymentHistorySection: some View {
        Section(header: Text("Payment History")) {
            if displayPaymentHistory.isEmpty {
                Text("No payments recorded")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(displayPaymentHistory, id: \.objectID) { transaction in
                    let isInitial = transaction == originalTransaction
                    PaymentHistoryRowView(
                        transaction: transaction,
                        currency: portfolioCurrency,
                        overrideAmount: isInitial ? firstPaymentDisplayAmount : nil,
                        overrideHasDiscount: isInitial ? firstPaymentHasDiscount : false
                    )
                }
            }
        }
    }


    private func isInsurancePayment(_ transaction: Transaction) -> Bool {
        isInsurancePaymentTransaction(transaction, asset: insuranceAsset, originalTransaction: originalTransaction)
    }

    private func isInsurancePaymentTransaction(_ transaction: Transaction,
                                               asset: Asset,
                                               originalTransaction: Transaction? = nil) -> Bool {
        guard let notesLowercased = transaction.notes?.lowercased() else { return false }

        if let original = originalTransaction,
           let identifier = CashDisciplineService.companionNoteIdentifier(for: original)?.lowercased(),
           notesLowercased.hasPrefix(identifier) {
            return true
        }

        if notesLowercased.contains("premium payment") {
            return true
        }

        if let symbol = asset.symbol?.lowercased(), !symbol.isEmpty, notesLowercased.contains(symbol) {
            return true
        }

        if let name = asset.name?.lowercased(), !name.isEmpty, notesLowercased.contains(name) {
            return true
        }

        return false
    }
}

struct PaymentHistoryRowView: View {
    @ObservedObject var transaction: Transaction
    let currency: Currency
    let overrideAmount: Double?
    let overrideHasDiscount: Bool

    private var transactionCurrency: Currency {
        Currency(rawValue: transaction.currency ?? currency.rawValue) ?? currency
    }

    private var paymentAmount: Double {
        let base = overrideAmount ?? transaction.amount
        return abs(base)
    }

    private var hasDiscount: Bool {
        if overrideHasDiscount {
            return overrideHasDiscount
        }

        guard let notes = transaction.notes?.lowercased() else { return false }
        return notes.contains("discount")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.transactionDate ?? Date(), style: .date)
                        .font(.headline)

                    if transaction.type == TransactionType.insurance.rawValue {
                        Text("Initial Policy Purchase")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        HStack {
                            Text("Premium Payment")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if hasDiscount {
                                Text("• Discount Applied")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                Spacer()

                Text(Formatters.currency(paymentAmount, symbol: transactionCurrency.symbol))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            if let institution = transaction.value(forKey: "paymentInstitutionName") as? String ?? transaction.tradingInstitution {
                Text("Paid from: \(institution)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = transaction.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

enum PaymentEntryType {
    case regular
}

// MARK: - Insurance Payment Entry

struct InsurancePaymentEntryView: View {
    @ObservedObject var portfolio: Portfolio
    @ObservedObject var insuranceAsset: Asset
    let paymentType: PaymentEntryType
    let expectedAmount: Double

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var paymentDate = Date()
    @State private var paymentAmount: Double = 0
    @State private var applyDiscount = false
    @State private var discountType: DiscountType = .percentage
    @State private var discountPercentage: Double = 0
    @State private var discountAmount: Double = 0
    @State private var selectedPaymentInstitution: Institution?
    @State private var notes = ""
    @State private var selectedCurrency = Currency.usd
    @State private var showingError = false
    @State private var errorMessage = ""

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Institution.name, ascending: true)],
        animation: .default
    ) private var institutions: FetchedResults<Institution>

    private let currencyService = CurrencyService.shared

    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var insurance: NSManagedObject? {
        insuranceAsset.value(forKey: "insurance") as? NSManagedObject
    }

    private var originalTransaction: Transaction? {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@ AND type == %@",
                                      insuranceAsset, portfolio, TransactionType.insurance.rawValue)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private var suggestedPaymentInstitution: Institution? {
        if let original = originalTransaction,
           let institutionName = original.value(forKey: "paymentInstitutionName") as? String {
            return institutions.first { $0.name?.caseInsensitiveCompare(institutionName) == .orderedSame }
        }
        return originalTransaction?.institution
    }

    private var finalPaymentAmount: Double {
        guard applyDiscount else { return paymentAmount }

        switch discountType {
        case .percentage:
            return paymentAmount * (1 - discountPercentage / 100)
        case .fixed:
            return max(0, paymentAmount - discountAmount)
        }
    }

    private var discountSavings: Double {
        paymentAmount - finalPaymentAmount
    }

    var body: some View {
        NavigationView {
            Form {
                paymentDetailsSection
                institutionSection
                summarySection
            }
            .navigationTitle("Premium Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePayment()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var paymentDetailsSection: some View {
        Section(header: Text("Payment Details")) {
            DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)

            Picker("Currency", selection: $selectedCurrency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            }
            .pickerStyle(MenuPickerStyle())

            HStack {
                Text("Expected Amount")
                Spacer()
                Text(Formatters.currency(expectedAmount, symbol: selectedCurrency.symbol))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Payment Amount")
                Spacer()
                TextField("0.00", value: $paymentAmount, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 120)
                Text(selectedCurrency.symbol)
                    .foregroundColor(.secondary)
            }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    @ViewBuilder
    private var discountSection: some View {
        Section(header: Text("First Payment Discount"), footer: Text("Apply discount for early or lump sum payment")) {
            Toggle("Apply Discount", isOn: $applyDiscount.animation())

            if applyDiscount {
                Picker("Discount Type", selection: $discountType) {
                    Text("Percentage").tag(DiscountType.percentage)
                    Text("Fixed Amount").tag(DiscountType.fixed)
                }
                .pickerStyle(SegmentedPickerStyle())

                switch discountType {
                case .percentage:
                    HStack {
                        Text("Discount Percentage")
                        Spacer()
                        TextField("0", value: $discountPercentage, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                case .fixed:
                    HStack {
                        Text("Discount Amount")
                        Spacer()
                        TextField("0.00", value: $discountAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(selectedCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                }

                if discountSavings > 0 {
                    HStack {
                        Text("Discount Savings")
                        Spacer()
                        Text(Formatters.currency(discountSavings, symbol: selectedCurrency.symbol))
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var institutionSection: some View {
        Section(header: Text("Payment Institution"), footer: Text("Select the institution where the payment will be deducted from")) {
            Picker("Institution", selection: $selectedPaymentInstitution) {
                Text("Select Institution").tag(Optional<Institution>.none)
                ForEach(institutions, id: \.objectID) { institution in
                    Text(institution.name ?? "Unknown").tag(Optional(institution))
                }
            }
            .pickerStyle(MenuPickerStyle())

            if let institution = selectedPaymentInstitution {
                let balance = institution.getCashBalance(for: portfolio)
                HStack {
                    Text("Available Balance")
                    Spacer()
                    Text(Formatters.currency(balance, symbol: portfolioCurrency.symbol))
                        .foregroundColor(balance >= convertToPortfolioCurrency(finalPaymentAmount) ? .green : .red)
                }
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section(header: Text("Payment Summary")) {

            HStack {
                Text("Final Payment Amount")
                Spacer()
                Text(Formatters.currency(finalPaymentAmount, symbol: selectedCurrency.symbol))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            if portfolio.enforcesCashDisciplineEnabled {
                Text("Cash will be deducted from the selected payment institution when saved")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    private var isFormValid: Bool {
        paymentAmount > 0 &&
        selectedPaymentInstitution != nil &&
        (!applyDiscount || (discountType == .percentage ? discountPercentage >= 0 : discountAmount >= 0))
    }

    private func setupInitialValues() {
        paymentAmount = expectedAmount

        if let original = originalTransaction,
           let originalCurrency = Currency(rawValue: original.currency ?? "") {
            selectedCurrency = originalCurrency
        } else {
            selectedCurrency = portfolioCurrency
        }

        selectedPaymentInstitution = suggestedPaymentInstitution

        notes = "Premium payment for \(insuranceAsset.name ?? insuranceAsset.symbol ?? "insurance policy")"
    }

    private func convertToPortfolioCurrency(_ amount: Double) -> Double {
        currencyService.convertAmount(amount, from: selectedCurrency, to: portfolioCurrency)
    }

    private func savePayment() {
        guard let paymentInstitution = selectedPaymentInstitution else {
            errorMessage = "Please select a payment institution"
            showingError = true
            return
        }

        if portfolio.enforcesCashDisciplineEnabled {
            let requiredFunds = convertToPortfolioCurrency(finalPaymentAmount)
            let availableFunds = paymentInstitution.getCashBalance(for: portfolio)

            if availableFunds < requiredFunds {
                errorMessage = "Insufficient funds in \(paymentInstitution.name ?? "selected institution"). Available: \(Formatters.currency(availableFunds, symbol: portfolioCurrency.symbol)), Required: \(Formatters.currency(requiredFunds, symbol: portfolioCurrency.symbol))"
                showingError = true
                return
            }
        }

        do {
            createInstallmentPayment(paymentInstitution: paymentInstitution)

            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save payment: \(error.localizedDescription)"
            showingError = true
            viewContext.rollback()
        }
    }

    private func findOrCreateDepositAsset(for category: DepositCategory) -> Asset {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, category.assetSymbol)

        if let existingAsset = try? viewContext.fetch(request).first {
            existingAsset.lastPriceUpdate = Date()
            return existingAsset
        }

        let newAsset = Asset(context: viewContext)
        newAsset.id = UUID()
        newAsset.symbol = category.assetSymbol
        newAsset.name = category.assetName
        newAsset.assetType = AssetType.deposit.rawValue
        newAsset.createdAt = Date()
        newAsset.lastPriceUpdate = Date()
        newAsset.currentPrice = 0
        return newAsset
    }

    private func updateFirstPayment(for transaction: Transaction, paymentInstitution: Institution) throws {
        transaction.transactionDate = paymentDate
        transaction.setValue(paymentInstitution.name, forKey: "paymentInstitutionName")
        transaction.currency = selectedCurrency.rawValue

        if portfolio.enforcesCashDisciplineEnabled {
            try updateCompanionDeposit(for: transaction, paymentInstitution: paymentInstitution)
        } else {
            adjustDirectDeduction(for: transaction, paymentInstitution: paymentInstitution)
        }

        appendDiscountNote(to: transaction)
        transaction.ensureIdentifiers()
    }

    private func updateCompanionDeposit(for transaction: Transaction, paymentInstitution: Institution) throws {
        guard let companion = CashDisciplineService.findCompanionDeposit(for: transaction, in: viewContext) else {
            throw NSError(domain: "InsurancePayment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate companion deposit for this insurance policy."])
        }

        TransactionImpactService.reverse(companion, in: portfolio, context: viewContext)

        companion.transactionDate = paymentDate
        companion.amount = -finalPaymentAmount
        companion.price = -finalPaymentAmount
        companion.quantity = 1
        companion.fees = 0
        companion.tax = 0
        companion.currency = selectedCurrency.rawValue
        companion.portfolio = portfolio
        companion.institution = paymentInstitution
        companion.tradingInstitution = paymentInstitution.name
        companion.autoFetchPrice = false
        companion.asset = findOrCreateDepositAsset(for: .demand)

        if let note = CashDisciplineService.companionNote(for: transaction, companionAmount: -finalPaymentAmount, currency: selectedCurrency) {
            companion.notes = applyDiscount ? note + discountSuffix() : note
        }

        companion.ensureIdentifiers()

        let cashDeltaPortfolio = currencyService.convertAmount(-finalPaymentAmount, from: selectedCurrency, to: portfolioCurrency)
        paymentInstitution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: -finalPaymentAmount)
        portfolio.addToCash(cashDeltaPortfolio)

        TransactionImpactService.recomputePortfolioTotals(for: portfolio)
    }

    private func adjustDirectDeduction(for transaction: Transaction, paymentInstitution: Institution) {
        let transactionCurrency = Currency(rawValue: transaction.currency ?? selectedCurrency.rawValue) ?? selectedCurrency
        let previousDeductedPortfolio = (transaction.value(forKey: "paymentDeductedAmount") as? Double) ?? 0
        let previousDeductedTransaction = currencyService.convertAmount(previousDeductedPortfolio, from: portfolioCurrency, to: transactionCurrency)

        let convertedFinal = currencyService.convertAmount(finalPaymentAmount, from: selectedCurrency, to: portfolioCurrency)
        let finalInTransactionCurrency = currencyService.convertAmount(finalPaymentAmount, from: selectedCurrency, to: transactionCurrency)

        if previousDeductedPortfolio != 0 {
            portfolio.addToCash(previousDeductedPortfolio)
            paymentInstitution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: previousDeductedTransaction)
        }

        portfolio.addToCash(-convertedFinal)
        paymentInstitution.addToCashBalance(for: portfolio, currency: transactionCurrency, delta: -finalInTransactionCurrency)

        transaction.setValue(true, forKey: "paymentDeducted")
        transaction.setValue(convertedFinal, forKey: "paymentDeductedAmount")

        TransactionImpactService.recomputePortfolioTotals(for: portfolio)
    }

    private func appendDiscountNote(to transaction: Transaction) {
        guard applyDiscount && discountSavings > 0 else { return }

        let baseNote = transaction.notes ?? ""
        let discountInfo = discountType == .percentage
        ? "\(discountPercentage)% discount (saved \(Formatters.currency(discountSavings, symbol: selectedCurrency.symbol)))"
        : "Discount applied (saved \(Formatters.currency(discountSavings, symbol: selectedCurrency.symbol)))"

        if baseNote.contains(discountInfo) { return }

        let separator = baseNote.isEmpty ? "" : "\n"
        transaction.notes = baseNote + separator + discountInfo
    }

    private func discountSuffix() -> String {
        guard applyDiscount && discountSavings > 0 else { return "" }

        let suffix: String
        switch discountType {
        case .percentage:
            suffix = " (discount: \(Formatters.decimal(discountPercentage))%)"
        case .fixed:
            suffix = " (discount: \(Formatters.currency(discountAmount, symbol: selectedCurrency.symbol)))"
        }

        return suffix
    }

    private func createInstallmentPayment(paymentInstitution: Institution) {
        let transaction = Transaction(context: viewContext)
        transaction.id = UUID()
        transaction.createdAt = Date()
        transaction.transactionDate = paymentDate
        transaction.type = TransactionType.deposit.rawValue
        transaction.amount = -finalPaymentAmount
        transaction.quantity = 1
        transaction.price = -finalPaymentAmount
        transaction.fees = 0
        transaction.tax = 0
        transaction.currency = selectedCurrency.rawValue
        transaction.portfolio = portfolio
        transaction.institution = paymentInstitution
        transaction.tradingInstitution = paymentInstitution.name
        transaction.autoFetchPrice = false

        var paymentNotes = notes
        if applyDiscount && discountSavings > 0 {
            let discountInfo = discountType == .percentage
                ? "\(discountPercentage)% discount"
                : "\(Formatters.currency(discountAmount, symbol: selectedCurrency.symbol)) discount"
            paymentNotes += " - \(discountInfo) applied (saved \(Formatters.currency(discountSavings, symbol: selectedCurrency.symbol)))"
        }

        paymentNotes += " - Related to \(insuranceAsset.symbol ?? insuranceAsset.name ?? "insurance policy")"
        transaction.notes = paymentNotes

        let depositAsset = findOrCreateDepositAsset(for: .demand)
        transaction.asset = depositAsset

        if portfolio.enforcesCashDisciplineEnabled {
            let convertedAmount = convertToPortfolioCurrency(finalPaymentAmount)
            portfolio.addToCash(-convertedAmount)
            paymentInstitution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: -finalPaymentAmount)
        }

        transaction.ensureIdentifiers()
    }
}

enum DiscountType: String, CaseIterable {
    case percentage = "percentage"
    case fixed = "fixed"

    var displayName: String {
        switch self {
        case .percentage: return "Percentage"
        case .fixed: return "Fixed Amount"
        }
    }
}
