import SwiftUI
import CoreData
import Foundation

struct AddTransactionView: View {
    let portfolio: Portfolio
    let transactionToEdit: Transaction?
    private let originalPaymentInstitutionName: String?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Institution.name, ascending: true)],
        animation: .default
    ) private var institutions: FetchedResults<Institution>
    
    @State private var selectedTransactionType = TransactionType.buy
    @State private var selectedAssetType = AssetType.stock
    @State private var assetSymbol = ""
    @State private var assetName = ""
    @State private var quantity: Double = 0
    @State private var price: Double = 0
    @State private var fees: Double = 0
    @State private var transactionDate = Date()
    @State private var notes = ""
    @State private var amount: Double = 0
    @State private var tradingInstitution = ""
    @State private var selectedInstitution: Institution? = nil
    @State private var showingCustomInstitution = false
    @State private var selectedPaymentInstitution: Institution? = nil
    @State private var tax: Double = 0
    @State private var selectedCurrency = Currency.usd
    @State private var hasMaturityDate = false
    @State private var maturityDate = Date()
    @State private var autoFetchPrice = true
    @State private var accruedInterest: Double = 0
    // Dividend-specific: source security
    @State private var selectedDividendAssetID: NSManagedObjectID?
    // Sell-specific: security to sell
    @State private var selectedSellAssetID: NSManagedObjectID?
    // Deposit-specific selection
    @State private var selectedDepositCategory = DepositCategory.demand
    @State private var depositInterestRate: Double = 0
    // Structured product fields
    @State private var structuredProductLinkedAssets = ""
    @State private var structuredProductInvestmentAmount: Double = 0
    @State private var structuredProductInterestRate: Double = 0
    // Interest-specific selection
    @State private var selectedInterestSource: InterestSourceSelection = .demand

    // Insurance-specific fields
    @State private var insuranceType = "Life Insurance"
    @State private var insuranceSymbol = ""
    @State private var policyholder = ""
    @State private var insuredPerson = ""
    @State private var basicInsuredAmount: Double = 0
    @State private var additionalPaymentAmount: Double = 0
    @State private var deathBenefit: Double = 0
    @State private var isParticipating = false
    @State private var hasSupplementaryInsurance = false
    @State private var premiumPaymentTerm: Int32 = 0
    @State private var premiumPaymentStatus = "Paid"
    @State private var premiumPaymentType = "Lump Sum"
    @State private var singlePremium: Double = 0
    @State private var firstDiscountedPremium: Double = 0
    @State private var totalPremium: Double = 0
    @State private var coverageExpirationDate = Date()
    @State private var maturityBenefitRedemptionDate = Date()
    @State private var estimatedMaturityBenefit: Double = 0
    @State private var canWithdrawPremiums = false
    @State private var maxWithdrawalPercentage: Double = 0
    @State private var cashValue: Double = 0
    @State private var contactNumber = ""
    @State private var beneficiaries: [BeneficiaryData] = []

    private let currencyService = CurrencyService.shared
    @State private var cashDisciplineError: String?
    @State private var quantityValidationError: String?

    init(portfolio: Portfolio, transactionToEdit: Transaction? = nil) {
        self.portfolio = portfolio
        self.transactionToEdit = transactionToEdit
        self.originalPaymentInstitutionName = transactionToEdit?.value(forKey: "paymentInstitutionName") as? String

        let defaultDate = Date()
        let initialType = transactionToEdit.flatMap { TransactionType(rawValue: $0.type ?? "") } ?? .buy
        let initialAssetType: AssetType
        if let rawType = transactionToEdit?.asset?.assetType,
           let resolved = AssetType(rawValue: rawType) {
            initialAssetType = resolved
        } else {
            initialAssetType = .stock
        }

        _selectedTransactionType = State(initialValue: initialType)
        _selectedAssetType = State(initialValue: initialAssetType)
        _assetSymbol = State(initialValue: transactionToEdit?.asset?.symbol ?? "")
        _assetName = State(initialValue: transactionToEdit?.asset?.name ?? "")
        _quantity = State(initialValue: transactionToEdit?.quantity ?? 0)
        _price = State(initialValue: transactionToEdit?.price ?? 0)
        _fees = State(initialValue: transactionToEdit?.fees ?? 0)

        // Initialize accrued interest for sell transactions
        let initialAccruedInterest: Double
        if let transaction = transactionToEdit, initialType == .sell {
            initialAccruedInterest = max(0, transaction.amount - (transaction.quantity * transaction.price))
        } else {
            initialAccruedInterest = 0
        }
        _accruedInterest = State(initialValue: initialAccruedInterest)
        _transactionDate = State(initialValue: transactionToEdit?.transactionDate ?? defaultDate)
        _notes = State(initialValue: transactionToEdit?.notes ?? "")
        _amount = State(initialValue: transactionToEdit?.amount ?? 0)
        _tradingInstitution = State(initialValue: transactionToEdit?.tradingInstitution ?? "")
        _selectedInstitution = State(initialValue: transactionToEdit?.institution)
        let shouldUseCustomInstitution = (transactionToEdit?.value(forKey: "institution") as? Institution) == nil && !(transactionToEdit?.tradingInstitution?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        _showingCustomInstitution = State(initialValue: shouldUseCustomInstitution)
        _tax = State(initialValue: transactionToEdit?.tax ?? 0)

        let defaultCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
        let initialCurrency = transactionToEdit.flatMap { Currency(rawValue: $0.currency ?? "") } ?? defaultCurrency
        _selectedCurrency = State(initialValue: initialCurrency)

        let initialDepositCategory: DepositCategory
        if initialType == .deposit {
            let existingDepositValue = transactionToEdit?.asset?.symbol ?? transactionToEdit?.asset?.name
            initialDepositCategory = DepositCategory.resolve(from: existingDepositValue) ?? .demand
        } else {
            initialDepositCategory = .demand
        }
        _selectedDepositCategory = State(initialValue: initialDepositCategory)

        let initialInterestRate: Double
        if initialType == .deposit {
            if let transactionRate = transactionToEdit?.value(forKey: "interestRate") as? Double {
                initialInterestRate = transactionRate
            } else if let assetRate = transactionToEdit?.asset?.value(forKey: "interestRate") as? Double {
                initialInterestRate = assetRate
            } else {
                initialInterestRate = 0
            }
        } else {
            initialInterestRate = 0
        }
        _depositInterestRate = State(initialValue: initialInterestRate)

        let isEditingStructuredProduct = transactionToEdit?.asset?.assetType == AssetType.structuredProduct.rawValue
        let hasMaturity: Bool
        if isEditingStructuredProduct {
            hasMaturity = transactionToEdit?.maturityDate != nil
        } else {
            hasMaturity = (transactionToEdit?.maturityDate != nil) && (initialType != .deposit || initialDepositCategory == .fixed)
        }
        _hasMaturityDate = State(initialValue: hasMaturity)
        _maturityDate = State(initialValue: transactionToEdit?.maturityDate ?? defaultDate)
        let defaultAutoFetch: Bool
        if initialType == .buy {
            defaultAutoFetch = transactionToEdit?.autoFetchPrice ?? false
        } else {
            defaultAutoFetch = transactionToEdit?.autoFetchPrice ?? true
        }
        _autoFetchPrice = State(initialValue: defaultAutoFetch)

        let initialStructuredLinkedAssets = isEditingStructuredProduct ? (transactionToEdit?.asset?.value(forKey: "linkedAssets") as? String ?? "") : ""
        let initialStructuredInterestRate = isEditingStructuredProduct ? (transactionToEdit?.asset?.value(forKey: "interestRate") as? Double ?? 0) : 0
        // For structured products, quantity and price are loaded directly from the transaction
        _structuredProductLinkedAssets = State(initialValue: initialStructuredLinkedAssets)
        _structuredProductInterestRate = State(initialValue: initialStructuredInterestRate)

        if initialType == .interest {
            let demandSymbol = DepositCategory.demand.assetSymbol.lowercased()
            if let asset = transactionToEdit?.asset {
                let isDemandAsset = asset.symbol?.lowercased() == demandSymbol ||
                    asset.name?.lowercased() == demandSymbol

                if isDemandAsset {
                    _selectedInterestSource = State(initialValue: .demand)
                } else if asset.assetType == AssetType.deposit.rawValue,
                          let institution = transactionToEdit?.institution {
                    _selectedInterestSource = State(initialValue: .fixedDeposit(institution.objectID))
                } else {
                    _selectedInterestSource = State(initialValue: .security(asset.objectID))
                }
            } else if let institution = transactionToEdit?.institution {
                _selectedInterestSource = State(initialValue: .fixedDeposit(institution.objectID))
            } else {
                _selectedInterestSource = State(initialValue: .demand)
            }
        } else {
            _selectedInterestSource = State(initialValue: .demand)
        }
        // No longer need structuredProductInvestmentAmount - using quantity and price directly

        if initialType == .dividend {
            _selectedDividendAssetID = State(initialValue: transactionToEdit?.asset?.objectID)
        } else {
            _selectedDividendAssetID = State(initialValue: nil)
        }

        if initialType == .sell {
            _selectedSellAssetID = State(initialValue: transactionToEdit?.asset?.objectID)
        } else {
            _selectedSellAssetID = State(initialValue: nil)
        }

        let insuranceObject = transactionToEdit?.asset?.value(forKey: "insurance") as? NSManagedObject
        _insuranceType = State(initialValue: (insuranceObject?.value(forKey: "insuranceType") as? String) ?? "Life Insurance")
        _insuranceSymbol = State(initialValue: transactionToEdit?.asset?.symbol ?? "")
        _policyholder = State(initialValue: (insuranceObject?.value(forKey: "policyholder") as? String) ?? "")
        _insuredPerson = State(initialValue: (insuranceObject?.value(forKey: "insuredPerson") as? String) ?? "")
        _basicInsuredAmount = State(initialValue: insuranceObject?.value(forKey: "basicInsuredAmount") as? Double ?? 0)
        _additionalPaymentAmount = State(initialValue: insuranceObject?.value(forKey: "additionalPaymentAmount") as? Double ?? 0)
        _deathBenefit = State(initialValue: insuranceObject?.value(forKey: "deathBenefit") as? Double ?? 0)
        _isParticipating = State(initialValue: insuranceObject?.value(forKey: "isParticipating") as? Bool ?? false)
        _hasSupplementaryInsurance = State(initialValue: insuranceObject?.value(forKey: "hasSupplementaryInsurance") as? Bool ?? false)
        _premiumPaymentTerm = State(initialValue: insuranceObject?.value(forKey: "premiumPaymentTerm") as? Int32 ?? 0)
        _premiumPaymentStatus = State(initialValue: (insuranceObject?.value(forKey: "premiumPaymentStatus") as? String) ?? "Paid")
        _premiumPaymentType = State(initialValue: (insuranceObject?.value(forKey: "premiumPaymentType") as? String) ?? "Lump Sum")
        _singlePremium = State(initialValue: insuranceObject?.value(forKey: "singlePremium") as? Double ?? 0)
        _firstDiscountedPremium = State(initialValue: insuranceObject?.value(forKey: "firstDiscountedPremium") as? Double ?? 0)
        _totalPremium = State(initialValue: insuranceObject?.value(forKey: "totalPremium") as? Double ?? 0)
        _coverageExpirationDate = State(initialValue: insuranceObject?.value(forKey: "coverageExpirationDate") as? Date ?? defaultDate)
        _maturityBenefitRedemptionDate = State(initialValue: insuranceObject?.value(forKey: "maturityBenefitRedemptionDate") as? Date ?? defaultDate)
        _estimatedMaturityBenefit = State(initialValue: insuranceObject?.value(forKey: "estimatedMaturityBenefit") as? Double ?? 0)
        _canWithdrawPremiums = State(initialValue: insuranceObject?.value(forKey: "canWithdrawPremiums") as? Bool ?? false)
        _maxWithdrawalPercentage = State(initialValue: insuranceObject?.value(forKey: "maxWithdrawalPercentage") as? Double ?? 0)
        _cashValue = State(initialValue: transactionToEdit?.amount ?? 0)
        _contactNumber = State(initialValue: (insuranceObject?.value(forKey: "contactNumber") as? String) ?? "")

        if let beneficiariesSet = insuranceObject?.value(forKey: "beneficiaries") as? Set<NSManagedObject>, !beneficiariesSet.isEmpty {
            let sorted = beneficiariesSet.sorted { lhs, rhs in
                let leftName = lhs.value(forKey: "name") as? String ?? ""
                let rightName = rhs.value(forKey: "name") as? String ?? ""
                return leftName < rightName
            }
            let mapped = sorted.map { beneficiary -> BeneficiaryData in
                let name = beneficiary.value(forKey: "name") as? String ?? ""
                let percentage = beneficiary.value(forKey: "percentage") as? Double ?? 0
                return BeneficiaryData(name: name, percentage: percentage)
            }
            _beneficiaries = State(initialValue: mapped)
        } else {
            _beneficiaries = State(initialValue: [])
        }

        if initialType == .insurance, transactionToEdit != nil, (_beneficiaries.wrappedValue).isEmpty {
            _beneficiaries = State(initialValue: [BeneficiaryData(name: "", percentage: 100)])
        }

        let context = transactionToEdit?.managedObjectContext ?? portfolio.managedObjectContext
        var initialPaymentInstitution: Institution?
        if initialType == .insurance {
            if let name = originalPaymentInstitutionName,
               let context = context {
                let request: NSFetchRequest<Institution> = Institution.fetchRequest()
                request.predicate = NSPredicate(format: "name ==[c] %@", name)
                request.fetchLimit = 1
                initialPaymentInstitution = try? context.fetch(request).first
            }
            if initialPaymentInstitution == nil {
                initialPaymentInstitution = transactionToEdit?.institution
            }
        }
        _selectedPaymentInstitution = State(initialValue: initialPaymentInstitution)

        _cashDisciplineError = State(initialValue: nil)
        _quantityValidationError = State(initialValue: nil)
    }
    
    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private var isAmountOnly: Bool {
        selectedTransactionType == .dividend || selectedTransactionType == .interest || selectedTransactionType == .deposit || selectedTransactionType == .insurance
    }
    
    private var requiresTax: Bool {
        selectedTransactionType == .sell || selectedTransactionType == .dividend || selectedTransactionType == .interest
    }

    private var isMaturityToggleDisabled: Bool {
        selectedTransactionType == .deposit && selectedDepositCategory != .fixed
    }

    private var isStructuredProductBuy: Bool {
        selectedTransactionType == .buy && selectedAssetType == .structuredProduct
    }

    private var activeInstitutionSelection: Institution? {
        if let institution = selectedInstitution {
            return institution
        }
        if let editingInstitution = transactionToEdit?.institution {
            return editingInstitution
        }
        let trimmed = tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return findExistingInstitution(name: trimmed)
    }

    private var settlementAmountForDisplay: Double {
        let baseAmount = quantity * price
        return baseAmount + fees
    }

    private var incomeSettlementAmountForDisplay: Double {
        let grossAmount = isAmountOnly ? amount : (quantity * price)
        return grossAmount - fees - tax
    }

    private var sellSettlementAmountForDisplay: Double {
        let grossAmount = (quantity * price) + accruedInterest
        return grossAmount - fees - tax
    }

    private var selectedSellAsset: Asset? {
        if let sellID = selectedSellAssetID {
            if let asset = sellSourceAssets.first(where: { $0.objectID == sellID }) {
                return asset
            }
            if let existingAsset = try? viewContext.existingObject(with: sellID) as? Asset {
                return existingAsset
            }
        }
        if selectedTransactionType == .sell, let editingAsset = transactionToEdit?.asset {
            return editingAsset
        }
        return nil
    }

    private var isStructuredProductSell: Bool {
        guard selectedTransactionType == .sell else { return false }
        return selectedSellAsset?.assetType == AssetType.structuredProduct.rawValue
    }

    private var isStructuredProductTransaction: Bool {
        isStructuredProductBuy || isStructuredProductSell
    }

    private var availableInstitutions: [Institution] {
        var results: [Institution] = []
        for institution in institutions {
            guard let name = institution.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            results.append(institution)
        }
        return results
    }

    private var isEditing: Bool {
        transactionToEdit != nil
    }

    var body: some View {
        NavigationView {
            Form {
                // Transaction Type
                Section(header: Text("Transaction Type")) {
                    Picker("Type", selection: $selectedTransactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // Currency Selection
                Section(header: Text("Currency")) {
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Trading Institution
                Section(header: Text("Trading Institution")) {
                    if availableInstitutions.isEmpty || showingCustomInstitution {
                        HStack {
                            TextField("Institution (e.g., Interactive Brokers)", text: $tradingInstitution)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            if !availableInstitutions.isEmpty {
                                Button("Select") {
                                    showingCustomInstitution = false
                                }
                                .font(.caption)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Picker("Institution", selection: $selectedInstitution) {
                                Text("Select Institution").tag(Optional<Institution>.none)
                                ForEach(availableInstitutions, id: \.objectID) { institution in
                                    Text(institution.name ?? "Unknown").tag(Optional(institution))
                                }
                            }
                            .pickerStyle(MenuPickerStyle())

                            Button("Type new institution") {
                                selectedInstitution = nil
                                showingCustomInstitution = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }

                    if selectedTransactionType == .insurance {
                        if availableInstitutions.isEmpty {
                            Text("Add an institution to enable payment selection.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Payment Institution", selection: $selectedPaymentInstitution) {
                                Text("Select Payment Institution").tag(Optional<Institution>.none)
                                ForEach(availableInstitutions, id: \.objectID) { institution in
                                    Text(institution.name ?? "Unknown").tag(Optional(institution))
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                }
                
                // Asset Information (Buy) or Sell Source selection
                assetInformationSection
                // Dividend Source (only for dividends)
                if selectedTransactionType == .dividend {
                    Section(header: Text("Dividend Source"), footer: Text("Select the security that generated this dividend.")) {
                        Picker("Security", selection: $selectedDividendAssetID) {
                            Text("None").tag(Optional<NSManagedObjectID>.none)
                            ForEach(dividendSourceAssets, id: \.objectID) { asset in
                                Text(asset.symbol ?? asset.name ?? "Unknown")
                                    .tag(Optional(asset.objectID))
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }

                if selectedTransactionType == .interest {
                    Section(header: Text("Interest Source"), footer: Text("Select the account or security that generated this interest.")) {
                        Picker("Source", selection: $selectedInterestSource) {
                            ForEach(interestSourceOptions) { option in
                                Text(option.title)
                                    .tag(option.selection)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                // Transaction Details
                transactionDetailsSection

                // Insurance-specific sections
                if selectedTransactionType == .insurance {
                    Section(header: Text("Insurance Details")) {
                        TextField("Policy Symbol", text: $insuranceSymbol)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        Picker("Insurance Type", selection: $insuranceType) {
                            Text("Life Insurance").tag("Life Insurance")
                            Text("Critical Illness Insurance").tag("Critical Illness Insurance")
                            Text("Accident Insurance").tag("Accident Insurance")
                        }
                        .pickerStyle(MenuPickerStyle())

                        TextField("Policyholder", text: $policyholder)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Insured Person", text: $insuredPerson)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Contact Number", text: $contactNumber)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.phonePad)
                    }

                    Section(header: Text("Financial Details")) {
                        HStack {
                            Text("Basic Insured Amount")
                            Spacer()
                            TextField("0.00", value: $basicInsuredAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Additional Payment")
                            Spacer()
                            TextField("0.00", value: $additionalPaymentAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Death Benefit")
                            Spacer()
                            TextField("0.00", value: $deathBenefit, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                    }

                    Section(header: Text("Premium Details")) {
                        HStack {
                            Text("Single Premium")
                            Spacer()
                            TextField("0.00", value: $singlePremium, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                                .onChange(of: singlePremium) { _, _ in
                                    calculateTotalPremium()
                                }
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("First Discounted Premium")
                            Spacer()
                            TextField("0.00", value: $firstDiscountedPremium, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                                .onChange(of: firstDiscountedPremium) { _, _ in
                                    calculateTotalPremium()
                                }
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Payment Term")
                            Spacer()
                            TextField("0", value: $premiumPaymentTerm, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .onChange(of: premiumPaymentTerm) { _, _ in
                                    calculateTotalPremium()
                                }
                        }

                        HStack {
                            Text("Total Premium")
                            Spacer()
                            TextField("0.00", value: $totalPremium, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }

                        Picker("Payment Status", selection: $premiumPaymentStatus) {
                            Text("Paid").tag("Paid")
                            Text("Paying").tag("Paying")
                        }
                        .pickerStyle(MenuPickerStyle())

                        Picker("Payment Type", selection: $premiumPaymentType) {
                            Text("Lump Sum").tag("Lump Sum")
                            Text("Installment").tag("Installment")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Section(header: Text("Policy Features")) {
                        Toggle("Participating Policy", isOn: $isParticipating)
                        Toggle("Rider", isOn: $hasSupplementaryInsurance)
                        Toggle("Can Withdraw Premiums", isOn: $canWithdrawPremiums)

                        if canWithdrawPremiums {
                            HStack {
                                Text("Max Withdrawal %")
                                Spacer()
                                TextField("0", value: $maxWithdrawalPercentage, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 80)
                                Text("%")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section(header: Text("Important Dates")) {
                        DatePicker("Coverage Expiration", selection: $coverageExpirationDate, displayedComponents: .date)
                        DatePicker("Maturity Benefit Redemption", selection: $maturityBenefitRedemptionDate, displayedComponents: .date)

                        HStack {
                            Text("Estimated Maturity Benefit")
                            Spacer()
                            TextField("0.00", value: $estimatedMaturityBenefit, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Beneficiaries")) {
                        ForEach(beneficiaries.indices, id: \.self) { index in
                            HStack {
                                TextField("Beneficiary Name", text: $beneficiaries[index].name)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())

                                TextField("0", value: $beneficiaries[index].percentage, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 60)

                                Text("%")
                                    .foregroundColor(.secondary)

                                Button(action: {
                                    beneficiaries.remove(at: index)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        Button(action: {
                            beneficiaries.append(BeneficiaryData(name: "", percentage: 0))
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("Add Beneficiary")
                            }
                        }

                        if !beneficiaries.isEmpty {
                            let totalPercentage = beneficiaries.reduce(0) { $0 + $1.percentage }
                            HStack {
                                Text("Total Percentage:")
                                Spacer()
                                Text("\(totalPercentage, specifier: "%.1f")%")
                                    .fontWeight(.medium)
                                    .foregroundColor(totalPercentage == 100 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .onChange(of: selectedTransactionType) { _, newValue in
            // Validate quantity when transaction type changes
            validateSellQuantity()

            switch newValue {
            case .dividend:
                if selectedDividendAssetID == nil { selectedDividendAssetID = dividendSourceAssets.first?.objectID }
                selectedSellAssetID = nil
                selectedInterestSource = .demand
            case .sell:
                if selectedSellAssetID == nil { selectedSellAssetID = sellSourceAssets.first?.objectID }
                selectedDividendAssetID = nil
                selectedInterestSource = .demand
            case .interest:
                if let firstSelection = interestSourceOptions.first?.selection {
                    selectedInterestSource = firstSelection
                } else {
                    selectedInterestSource = .demand
                }
                selectedDividendAssetID = nil
                selectedSellAssetID = nil
                selectedPaymentInstitution = nil
            case .insurance:
                // Initialize with one beneficiary if empty
                if beneficiaries.isEmpty {
                    beneficiaries = [BeneficiaryData(name: "", percentage: 100)]
                }
                if selectedPaymentInstitution == nil {
                    selectedPaymentInstitution = selectedInstitution
                }
                selectedDividendAssetID = nil
                selectedSellAssetID = nil
                selectedInterestSource = .demand
            default:
                selectedDividendAssetID = nil
                selectedSellAssetID = nil
                selectedPaymentInstitution = nil
                selectedInterestSource = .demand
            }

            if newValue == .deposit && selectedDepositCategory != .fixed {
                hasMaturityDate = false
            }

            if newValue == .buy && isStructuredProductBuy {
                if quantity == 0 { quantity = 1 }
                if price == 0 { price = 0 }
            }
        }
        .onAppear {
            if selectedTransactionType == .insurance && selectedPaymentInstitution == nil {
                selectedPaymentInstitution = selectedInstitution
            }
            // Validate quantity on initial load
            validateSellQuantity()
        }
        .onChange(of: selectedInstitution) { _, newValue in
            if selectedTransactionType == .insurance && selectedPaymentInstitution == nil {
                selectedPaymentInstitution = newValue
            }

            // Reset selected sell asset when institution changes for sell transactions
            if selectedTransactionType == .sell {
                selectedSellAssetID = nil
            }

            if selectedTransactionType == .interest {
                if let firstSelection = interestSourceOptions.first?.selection {
                    selectedInterestSource = firstSelection
                }
            }
        }
        .onChange(of: tradingInstitution) { _, newValue in
            // Reset selected sell asset when trading institution text changes for sell transactions
            if selectedTransactionType == .sell {
                selectedSellAssetID = nil
            }

            if selectedTransactionType == .interest {
                if let firstSelection = interestSourceOptions.first?.selection {
                    selectedInterestSource = firstSelection
                }
            }
        }
        .onChange(of: selectedDepositCategory) { _, newValue in
            if selectedTransactionType == .deposit && newValue != .fixed {
                hasMaturityDate = false
            }
        }
        .onChange(of: selectedAssetType) { _, newValue in
            if newValue == .structuredProduct {
                if quantity == 0 { quantity = 1 }
                if price == 0 { price = 0 }
            } else if transactionToEdit?.asset?.assetType != AssetType.structuredProduct.rawValue {
                structuredProductLinkedAssets = ""
                structuredProductInterestRate = 0
            }
        }
        .onChange(of: selectedSellAssetID) { _, _ in
            // Validate quantity whenever selected sell asset changes
            validateSellQuantity()

            guard isStructuredProductSell, let asset = selectedSellAsset else { return }
            structuredProductLinkedAssets = asset.value(forKey: "linkedAssets") as? String ?? ""
            structuredProductInterestRate = asset.value(forKey: "interestRate") as? Double ?? 0
        }
        .alert("Cash Requirement", isPresented: Binding(get: { cashDisciplineError != nil }, set: { if !$0 { cashDisciplineError = nil } })) {
            Button("OK", role: .cancel) {
                cashDisciplineError = nil
            }
        } message: {
            if let message = cashDisciplineError {
                Text(message)
            }
        }
    }
    
    private var isFormValid: Bool {
        let hasValidInstitution = selectedInstitution != nil || !tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasQuantityValidationError = quantityValidationError != nil

        switch selectedTransactionType {
        case .dividend:
            return amount > 0 && hasValidInstitution
        case .interest:
            let hasSource = interestSourceOptions.contains { $0.selection == selectedInterestSource }
            return amount > 0 && hasValidInstitution && hasSource
        case .sell:
            let hasSelection = selectedSellAssetID != nil && hasValidInstitution
            if isStructuredProductSell {
                return hasSelection && quantity > 0 && price > 0 && !hasQuantityValidationError
            }
            return hasSelection && quantity > 0 && price > 0 && !hasQuantityValidationError
        case .buy:
            if isStructuredProductBuy {
                return !assetSymbol.isEmpty && quantity > 0 && price > 0 && hasValidInstitution
            }
            return !assetSymbol.isEmpty && quantity > 0 && price > 0 && hasValidInstitution
        case .deposit:
            return amount != 0 && hasValidInstitution
        case .insurance:
            let hasSymbol = !insuranceSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return cashValue > 0 && hasValidInstitution && hasSymbol
        }
    }
    
    private func saveTransaction() {
        let trimmedInstitutionName = tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedTransactionType == .insurance {
            insuranceSymbol = insuranceSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        var createdInstitution: Institution?
        var institutionForTransaction: Institution? = selectedInstitution
        if institutionForTransaction == nil, !trimmedInstitutionName.isEmpty {
            let (institution, wasCreated) = findOrCreateInstitution(name: trimmedInstitutionName)
            institutionForTransaction = institution
            if wasCreated { createdInstitution = institution }
            if selectedPaymentInstitution == nil {
                selectedPaymentInstitution = institution
            }
        }

        let existingTransaction = transactionToEdit
        let existingTransactionType = existingTransaction.flatMap { TransactionType(rawValue: $0.type ?? "") }
        let cashDisciplineEnabled = portfolio.enforcesCashDisciplineEnabled

        func failWithMessage(_ message: String) {
            if let createdInstitution = createdInstitution {
                viewContext.delete(createdInstitution)
            }
            cashDisciplineError = message
        }

        var preselectedSellAsset: Asset?

        // For structured products, use the user-entered quantity and price directly

        if selectedTransactionType == .sell {
            guard let sellID = selectedSellAssetID,
                  let sellAsset = try? viewContext.existingObject(with: sellID) as? Asset else {
                failWithMessage("Select a holding to sell before saving.")
                return
            }

            // For structured products, use the user-entered quantity and price directly

            let holdingFetch: NSFetchRequest<Holding> = Holding.fetchRequest()
            if let institution = institutionForTransaction {
                holdingFetch.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@ AND institution == %@", sellAsset, portfolio, institution)
            } else {
                holdingFetch.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@ AND institution == nil", sellAsset, portfolio)
            }
            holdingFetch.fetchLimit = 1

            let availableQuantity = (try? viewContext.fetch(holdingFetch).first?.quantity) ?? 0
            let previousQuantity = (existingTransactionType == .sell && existingTransaction?.asset?.objectID == sellAsset.objectID) ? (existingTransaction?.quantity ?? 0) : 0
            if availableQuantity + previousQuantity + 1e-6 < quantity {
                failWithMessage("Not enough shares available to sell. You currently hold \(Formatters.decimal(availableQuantity + previousQuantity)).")
                return
            }

            if let institution = institutionForTransaction,
               let validationMessage = validateHoldingInstitution(for: sellAsset, institution: institution) {
                failWithMessage(validationMessage)
                return
            }

            preselectedSellAsset = sellAsset
        }

        if cashDisciplineEnabled {
            switch selectedTransactionType {
            case .buy:
                guard let institution = institutionForTransaction else {
                    failWithMessage("Select a trading institution before purchasing securities.")
                    return
                }
                let requiredFundsTransactionCurrency = (quantity * price + fees + tax)
                let transactionCurrency = selectedCurrency
                let requiredFunds = max(0, requiredFundsTransactionCurrency)
                var availableFunds = portfolio.getCurrencyBalance(for: institution, currency: transactionCurrency.rawValue)
                if let existingTransaction,
                   existingTransactionType == .buy,
                   (existingTransaction.value(forKey: "institution") as? Institution)?.objectID == institution.objectID {
                    let previousCurrency = Currency(rawValue: existingTransaction.currency ?? transactionCurrency.rawValue) ?? transactionCurrency
                    let previousCost = (existingTransaction.quantity * existingTransaction.price) + existingTransaction.fees + existingTransaction.tax
                    let restoredAmount = currencyService.convertAmount(previousCost, from: previousCurrency, to: transactionCurrency)
                    availableFunds += restoredAmount
                }
                if availableFunds + 1e-6 < requiredFunds {
                    let institutionName = institution.name ?? "this institution"
                    let formattedAvailable = currencyService.formatAmountWithFullCurrency(availableFunds, in: transactionCurrency)
                    let formattedRequired = currencyService.formatAmountWithFullCurrency(requiredFunds, in: transactionCurrency)
                    failWithMessage("Not enough cash in \(institutionName) to complete this purchase. Current balance: \(formattedAvailable). Required: \(formattedRequired). If you do not want cash to be deducted at the time of purchase, you can go to the portfolio settings to turn off 'Enforce Cash Discipline'.")
                    return
                }
            case .insurance:
                let paymentInstitution = selectedPaymentInstitution ?? institutionForTransaction
                guard let paymentInstitution = paymentInstitution else {
                    failWithMessage("Select a payment institution for this insurance policy.")
                    return
                }
                let premiumAmount = max(0, initialInsurancePaymentAmount())
                let requiredFunds = max(0, convertToPortfolioCurrency(premiumAmount, from: selectedCurrency))
                var availableFunds = paymentInstitution.getCashBalance(for: portfolio)
                if let existingTransaction,
                   existingTransactionType == .insurance {
                    let previousInstitutionName = existingTransaction.value(forKey: "paymentInstitutionName") as? String ?? (existingTransaction.value(forKey: "institution") as? Institution)?.name
                    if let previousInstitutionName = previousInstitutionName,
                       let currentName = paymentInstitution.name,
                       previousInstitutionName.caseInsensitiveCompare(currentName) == .orderedSame {
                        let previouslyDeducted = existingTransaction.value(forKey: "paymentDeductedAmount") as? Double ?? 0
                        availableFunds += previouslyDeducted
                    }
                }
                if availableFunds + 1e-6 < requiredFunds {
                    failWithMessage("Not enough cash in \(paymentInstitution.name ?? "this institution") to purchase this insurance policy. If you do not want cash to be deducted at the time of purchase, you can go to the portfolio settings to turn off 'Enforce Cash Discipline'.")
                    return
                }
            case .deposit:
                guard let institution = institutionForTransaction else {
                    failWithMessage("Select a trading institution for this transaction.")
                    return
                }
                // Check for withdrawal (negative amount) if amount < 0
                if amount < 0 {
                    let withdrawalAmount = abs(amount)
                    let netWithdrawal = withdrawalAmount + fees + tax  // fees and tax add to the withdrawal cost
                    let convertedWithdrawal = convertToPortfolioCurrency(netWithdrawal, from: selectedCurrency)
                    if institution.getCashBalance(for: portfolio) < convertedWithdrawal {
                        let institutionName = institution.name ?? "this institution"
                        let currentBalance = currencyService.formatAmount(institution.getCashBalance(for: portfolio), in: portfolioCurrency)
                        let requiredAmount = currencyService.formatAmount(convertedWithdrawal, in: portfolioCurrency)
                        failWithMessage("Not enough cash in \(institutionName) for this withdrawal. Current balance: \(currentBalance), Required: \(requiredAmount).")
                        return
                    }
                }
            case .sell:
                guard institutionForTransaction != nil else {
                    failWithMessage("Select a trading institution for this transaction.")
                    return
                }
            default:
                break
            }
        }

        if selectedTransactionType == .insurance {
            guard !policyholder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failWithMessage("Policyholder name is required for insurance transactions.")
                return
            }
            guard !insuredPerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failWithMessage("Insured person name is required for insurance transactions.")
                return
            }
            guard !beneficiaries.isEmpty else {
                failWithMessage("At least one beneficiary is required for insurance policies.")
                return
            }
            let totalPercentage = beneficiaries.reduce(0) { $0 + $1.percentage }
            guard abs(totalPercentage - 100.0) < 0.01 else {
                failWithMessage("Beneficiary percentages must total 100%.")
                return
            }
            for beneficiary in beneficiaries {
                guard !beneficiary.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    failWithMessage("All beneficiary names are required.")
                    return
                }
            }
        }

        let transaction = existingTransaction ?? Transaction(context: viewContext)

        if let existingTransaction = existingTransaction {
            TransactionImpactService.reverse(existingTransaction, in: portfolio, context: viewContext)
        } else {
            transaction.id = UUID()
            transaction.createdAt = Date()
        }

        if selectedTransactionType == .dividend {
            guard let dividendAssetID = selectedDividendAssetID,
                  let dividendAsset = try? viewContext.existingObject(with: dividendAssetID) as? Asset else {
                failWithMessage("Select the asset that generated this dividend.")
                return
            }

            if let validationMessage = validateIncomeCurrency(for: dividendAsset, currency: selectedCurrency) {
                failWithMessage(validationMessage)
                return
            }
        }

        let previousAsset = transaction.asset

        if transaction.createdAt == nil {
            transaction.createdAt = Date()
        }

        transaction.type = selectedTransactionType.rawValue
        transaction.transactionDate = transactionDate
        transaction.fees = fees
        transaction.tax = tax
        transaction.currency = selectedCurrency.rawValue
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.maturityDate = hasMaturityDate ? maturityDate : nil
        transaction.autoFetchPrice = autoFetchPrice
        transaction.portfolio = portfolio
        transaction.ensureIdentifiers()

        if let institution = institutionForTransaction {
            transaction.institution = institution
            if let name = institution.name, !name.isEmpty {
                transaction.tradingInstitution = name
            } else if !trimmedInstitutionName.isEmpty {
                transaction.tradingInstitution = trimmedInstitutionName
            } else {
                transaction.tradingInstitution = nil
            }
        } else {
            transaction.institution = nil
            transaction.tradingInstitution = trimmedInstitutionName.isEmpty ? nil : trimmedInstitutionName
        }

        let resolvedPaymentInstitution = selectedPaymentInstitution ?? institutionForTransaction
        transaction.setValue(resolvedPaymentInstitution?.name, forKey: "paymentInstitutionName")

        let hadExistingInsurancePayment = (existingTransactionType == .insurance && existingTransaction != nil)
        let previousPaymentDeducted = existingTransaction?.value(forKey: "paymentDeducted") as? Bool ?? false
        let previousPaymentDeductedAmount = existingTransaction?.value(forKey: "paymentDeductedAmount") as? Double ?? 0

        if hadExistingInsurancePayment {
            transaction.setValue(previousPaymentDeducted, forKey: "paymentDeducted")
            transaction.setValue(previousPaymentDeductedAmount, forKey: "paymentDeductedAmount")
        } else {
            transaction.setValue(false, forKey: "paymentDeducted")
            transaction.setValue(0.0, forKey: "paymentDeductedAmount")
        }
        transaction.realizedGainAmount = 0
        transaction.asset = nil

        if isAmountOnly {
            if selectedTransactionType == .insurance {
                transaction.amount = cashValue
                transaction.quantity = 1
                transaction.price = cashValue

                let premiumAmount = max(0, initialInsurancePaymentAmount())
                if premiumAmount > 0, let paymentInstitution = resolvedPaymentInstitution {
                    if cashDisciplineEnabled {
                        transaction.setValue(false, forKey: "paymentDeducted")
                        transaction.setValue(0.0, forKey: "paymentDeductedAmount")
                    } else {
                        let convertedPremium = convertToPortfolioCurrency(premiumAmount, from: selectedCurrency)
                        portfolio.addToCash(-convertedPremium)
                        paymentInstitution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: -premiumAmount)
                        transaction.setValue(true, forKey: "paymentDeducted")
                        transaction.setValue(convertedPremium, forKey: "paymentDeductedAmount")
                        transaction.setValue(paymentInstitution.name, forKey: "paymentInstitutionName")
                    }
                }
            } else {
                transaction.amount = amount
                transaction.quantity = 1
                transaction.price = amount

                if selectedTransactionType == .deposit {
                    let depositAsset = findOrCreateDepositAsset(for: selectedDepositCategory, existingAsset: previousAsset)
                    transaction.asset = depositAsset
                    transaction.setValue(depositInterestRate, forKey: "interestRate")
                }

                let netCash = amount - fees - tax
                switch selectedTransactionType {
                case .deposit:
                    // For deposits, allow negative amounts (withdrawals)
                    let convertedNetCash = convertToPortfolioCurrency(netCash, from: selectedCurrency)
                    if let institution = institutionForTransaction {
                        institution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: netCash)
                    }

                    portfolio.addToCash(convertedNetCash)
                case .dividend:
                    guard let institution = institutionForTransaction else {
                        failWithMessage("Select an institution to record dividend income.")
                        return
                    }

                    institution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: netCash)

                    if let assetID = selectedDividendAssetID,
                       let srcAsset = try? viewContext.existingObject(with: assetID) as? Asset {
                        transaction.asset = srcAsset
                        maintainInstitutionAssetRelationship(institution: institution, asset: srcAsset, transactionDate: transactionDate)

                        let demandAsset = findOrCreateDepositAsset(for: .demand, existingAsset: nil)
                        maintainInstitutionAssetRelationship(institution: institution, asset: demandAsset, transactionDate: transactionDate)

                        if let message = validateHoldingInstitution(for: srcAsset, institution: institution) {
                            failWithMessage(message)
                            return
                        }

                        if let holding = holdingForAsset(srcAsset, institution: institution) ?? holdingForAsset(srcAsset, institution: nil) {
                            if currentInstitution(of: holding) == nil {
                                assignInstitution(institution, to: holding)
                            }
                        }

                        recordIncome(for: srcAsset, netAmount: netCash, transactionCurrency: selectedCurrency, institution: institution)
                    }
                case .interest:
                    guard let institution = institutionForTransaction else {
                        failWithMessage("Select an institution to record interest income.")
                        return
                    }

                    institution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: netCash)

                    if let option = interestSourceOption(for: selectedInterestSource) ?? interestSourceOptions.first {
                        switch option.selection {
                        case .demand:
                            if let assetID = option.assetID,
                               let demandAsset = try? viewContext.existingObject(with: assetID) as? Asset {
                                transaction.asset = demandAsset
                            } else {
                                let demandAsset = findOrCreateDepositAsset(for: .demand, existingAsset: previousAsset)
                                transaction.asset = demandAsset
                            }

                            if let demandAsset = transaction.asset,
                               let holding = holdingForAsset(demandAsset, institution: institution) ?? holdingForAsset(demandAsset, institution: nil) {
                                if currentInstitution(of: holding) == nil {
                                    assignInstitution(institution, to: holding)
                                }

                                recordIncome(for: demandAsset, netAmount: netCash, transactionCurrency: selectedCurrency, institution: institution)
                            }
                        case .fixedDeposit(let institutionID):
                            let depositAsset: Asset?
                            if let assetID = option.assetID,
                               let resolvedAsset = try? viewContext.existingObject(with: assetID) as? Asset {
                                depositAsset = resolvedAsset
                            } else {
                                depositAsset = findOrCreateDepositAsset(for: .fixed, existingAsset: previousAsset)
                            }

                            if let depositAsset {
                                transaction.asset = depositAsset

                                if let sourceInstitution = try? viewContext.existingObject(with: institutionID) as? Institution {
                                    maintainInstitutionAssetRelationship(institution: sourceInstitution, asset: depositAsset, transactionDate: transactionDate)
                                }

                                if let holding = holdingForAsset(depositAsset, institution: institution) ?? holdingForAsset(depositAsset, institution: nil) {
                                    if currentInstitution(of: holding) == nil {
                                        assignInstitution(institution, to: holding)
                                    }
                                }

                                recordIncome(for: depositAsset, netAmount: netCash, transactionCurrency: selectedCurrency, institution: institution)
                            }
                        case .security(let assetID):
                            if let securityAsset = try? viewContext.existingObject(with: assetID) as? Asset {
                                transaction.asset = securityAsset
                                maintainInstitutionAssetRelationship(institution: institution, asset: securityAsset, transactionDate: transactionDate)

                                if let message = validateHoldingInstitution(for: securityAsset, institution: institution) {
                                    failWithMessage(message)
                                    return
                                }

                                if let holding = holdingForAsset(securityAsset, institution: institution) ?? holdingForAsset(securityAsset, institution: nil) {
                                    if currentInstitution(of: holding) == nil {
                                        assignInstitution(institution, to: holding)
                                    }
                                }

                                recordIncome(for: securityAsset, netAmount: netCash, transactionCurrency: selectedCurrency, institution: institution)
                            }
                        }
                    }
                default:
                    break
                }
            }
        } else {
            transaction.quantity = quantity
            transaction.price = price
            transaction.amount = selectedTransactionType == .sell ? (quantity * price + accruedInterest) : (quantity * price)

            let asset: Asset
            if selectedTransactionType == .sell, let preselectedSellAsset {
                asset = preselectedSellAsset
            } else {
                asset = findOrCreateAsset()
            }
            transaction.asset = asset

            if isStructuredProductBuy {
                configureStructuredProductAsset(asset)
            } else if isStructuredProductSell, asset.assetType == AssetType.structuredProduct.rawValue {
                configureStructuredProductAsset(asset)
            }

            // Maintain institution-asset relationship for buy/sell transactions
            if let institution = institutionForTransaction {
                maintainInstitutionAssetRelationship(institution: institution, asset: asset, transactionDate: transactionDate)
            }

            if selectedTransactionType == .buy {
                if let message = validateHoldingInstitution(for: asset, institution: institutionForTransaction) {
                    failWithMessage(message)
                    return
                }
            }

            if let realizedGain = updateHolding(for: asset, transaction: transaction) {
                transaction.realizedGainAmount = realizedGain
            }

            if selectedTransactionType == .sell {
                let netProceeds = transaction.amount - fees - tax
                if netProceeds != 0 {
                    if cashDisciplineEnabled {
                        // Cash will be adjusted via companion deposit entry
                    } else {
                        let convertedProceeds = convertToPortfolioCurrency(netProceeds, from: selectedCurrency)
                        if let institution = institutionForTransaction {
                            institution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: netProceeds)
                        } else {
                            portfolio.addToCash(convertedProceeds)
                        }
                    }
                }
            } else if selectedTransactionType == .buy {
                let requiredFundsTransactionCurrency = (quantity * price) + fees + tax
                if cashDisciplineEnabled {
                    // Cash will be adjusted via companion deposit entry
                } else {
                    let requiredFunds = max(0, convertToPortfolioCurrency(requiredFundsTransactionCurrency, from: selectedCurrency))
                    if let institution = institutionForTransaction {
                        institution.addToCashBalance(for: portfolio, currency: selectedCurrency, delta: -requiredFundsTransactionCurrency)
                    } else {
                        portfolio.addToCash(-requiredFunds)
                    }
                }
            }
        }

        if selectedTransactionType == .insurance {
            let asset = createInsuranceAsset()
            transaction.asset = asset

            // Maintain institution-asset relationship for insurance transactions
            if let institution = institutionForTransaction {
                maintainInstitutionAssetRelationship(institution: institution, asset: asset, transactionDate: transactionDate)
            }

            let insurance = NSEntityDescription.insertNewObject(forEntityName: "Insurance", into: viewContext)
            insurance.setValue(UUID(), forKey: "id")
            insurance.setValue(insuranceType, forKey: "insuranceType")
            insurance.setValue(policyholder, forKey: "policyholder")
            insurance.setValue(insuredPerson, forKey: "insuredPerson")
            insurance.setValue(contactNumber, forKey: "contactNumber")
            insurance.setValue(basicInsuredAmount, forKey: "basicInsuredAmount")
            insurance.setValue(additionalPaymentAmount, forKey: "additionalPaymentAmount")
            insurance.setValue(deathBenefit, forKey: "deathBenefit")
            insurance.setValue(isParticipating, forKey: "isParticipating")
            insurance.setValue(hasSupplementaryInsurance, forKey: "hasSupplementaryInsurance")
            insurance.setValue(premiumPaymentTerm, forKey: "premiumPaymentTerm")
            insurance.setValue(premiumPaymentStatus, forKey: "premiumPaymentStatus")
            insurance.setValue(premiumPaymentType, forKey: "premiumPaymentType")
            insurance.setValue(singlePremium, forKey: "singlePremium")
            insurance.setValue(firstDiscountedPremium, forKey: "firstDiscountedPremium")
            insurance.setValue(totalPremium, forKey: "totalPremium")
            insurance.setValue(coverageExpirationDate, forKey: "coverageExpirationDate")
            insurance.setValue(maturityBenefitRedemptionDate, forKey: "maturityBenefitRedemptionDate")
            insurance.setValue(estimatedMaturityBenefit, forKey: "estimatedMaturityBenefit")
            insurance.setValue(canWithdrawPremiums, forKey: "canWithdrawPremiums")
            insurance.setValue(maxWithdrawalPercentage, forKey: "maxWithdrawalPercentage")
            insurance.setValue(Date(), forKey: "createdAt")
            insurance.setValue(asset, forKey: "asset")

            for beneficiaryData in beneficiaries {
                let beneficiary = NSEntityDescription.insertNewObject(forEntityName: "Beneficiary", into: viewContext)
                beneficiary.setValue(UUID(), forKey: "id")
                beneficiary.setValue(beneficiaryData.name, forKey: "name")
                beneficiary.setValue(beneficiaryData.percentage, forKey: "percentage")
                beneficiary.setValue(Date(), forKey: "createdAt")
                beneficiary.setValue(insurance, forKey: "insurance")
            }

            updateInsuranceHolding(for: asset, transaction: transaction)
        }

        manageCashDisciplineCompanion(for: transaction)

        recomputePortfolioTotals()

        do {
            try viewContext.save()
            print("✅ Transaction saved successfully: \(transaction.type ?? "Unknown") - \(transaction.amount)")

            dismiss()
        } catch {
            print("❌ Error saving transaction: \(error)")
            print("Transaction details: type=\(selectedTransactionType.rawValue), amount=\(transaction.amount), institution=\(tradingInstitution)")
            viewContext.rollback()
        }
    }

    private var dividendSourceAssets: [Asset] {
        guard let institution = activeInstitutionSelection else { return [] }

        let editingDividendAssetID = (selectedTransactionType == .dividend ? transactionToEdit?.asset?.objectID : nil)

        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let assets = holdings.compactMap { holding -> Asset? in
            guard holding.quantity > 0 else { return nil }
            guard let holdingInstitution = currentInstitution(of: holding),
                  holdingInstitution.objectID == institution.objectID else { return nil }
            guard let asset = holding.asset else { return nil }
            if let assetType = asset.assetType,
               (assetType == AssetType.bond.rawValue || assetType == AssetType.structuredProduct.rawValue),
               asset.objectID != editingDividendAssetID {
                return nil
            }
            return asset
        }

        var seen = Set<NSManagedObjectID>()
        var unique: [Asset] = []
        for asset in assets {
            if !seen.contains(asset.objectID) {
                unique.append(asset)
                seen.insert(asset.objectID)
            }
        }
        return unique.sorted { ($0.symbol ?? $0.name ?? "") < ($1.symbol ?? $1.name ?? "") }
    }

    private var interestSourceOptions: [InterestSourceOption] {
        guard let institution = activeInstitutionSelection else { return [] }

        let demandAssetID = fetchDepositAsset(for: .demand)?.objectID
        let demandTitle = DepositCategory.demand.displayTitle
        var options: [InterestSourceOption] = [
            InterestSourceOption(
                selection: .demand,
                title: demandTitle,
                assetID: demandAssetID,
                institutionID: nil
            )
        ]

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let fixedSymbol = DepositCategory.fixed.assetSymbol.lowercased()
        let fixedName = DepositCategory.fixed.assetName.lowercased()

        var seenInstitutions = Set<NSManagedObjectID>()
        var fixedOptions: [InterestSourceOption] = []

        for transaction in transactions {
            guard transaction.type == TransactionType.deposit.rawValue,
                  let asset = transaction.asset,
                  let txnInstitution = transaction.institution,
                  txnInstitution.objectID == institution.objectID else { continue }

            let symbolMatches = asset.symbol?.lowercased() == fixedSymbol
            let nameMatches = asset.name?.lowercased() == fixedName
            guard symbolMatches || nameMatches else { continue }

            let institutionID = txnInstitution.objectID
            if seenInstitutions.contains(institutionID) { continue }
            seenInstitutions.insert(institutionID)

            let displayName = (txnInstitution.name?.isEmpty == false) ? (txnInstitution.name ?? "Unknown Institution") : "Unknown Institution"

            fixedOptions.append(
                InterestSourceOption(
                    selection: .fixedDeposit(institutionID),
                    title: displayName,
                    assetID: asset.objectID,
                    institutionID: institutionID
                )
            )
        }

        if selectedTransactionType == .interest,
           let editingInstitution = transactionToEdit?.institution {
            let institutionID = editingInstitution.objectID
            if !seenInstitutions.contains(institutionID) {
                let displayName = (editingInstitution.name?.isEmpty == false) ? (editingInstitution.name ?? "Unknown Institution") : "Unknown Institution"
                fixedOptions.append(
                    InterestSourceOption(
                        selection: .fixedDeposit(institutionID),
                        title: displayName,
                        assetID: transactionToEdit?.asset?.objectID,
                        institutionID: institutionID
                    )
                )
            }
        }

        fixedOptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        options.append(contentsOf: fixedOptions)

        // Include interest-bearing securities (e.g., bonds, structured products) held at this institution
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let interestAssetTypes: Set<String> = [AssetType.bond.rawValue, AssetType.structuredProduct.rawValue]
        let interestAssets = holdings.compactMap { holding -> Asset? in
            guard holding.quantity > 0 else { return nil }
            guard let holdingInstitution = currentInstitution(of: holding),
                  holdingInstitution.objectID == institution.objectID else { return nil }
            guard let asset = holding.asset,
                  let assetType = asset.assetType,
                  interestAssetTypes.contains(assetType) else { return nil }
            return asset
        }

        var seenAssets = Set<NSManagedObjectID>()
        let securityOptions: [InterestSourceOption] = interestAssets.compactMap { asset in
            let assetID = asset.objectID
            if seenAssets.contains(assetID) { return nil }
            seenAssets.insert(assetID)
            let displayName = asset.symbol ?? asset.name ?? "Security"
            return InterestSourceOption(
                selection: .security(assetID),
                title: displayName,
                assetID: assetID,
                institutionID: institution.objectID
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        options.append(contentsOf: securityOptions)

        if selectedTransactionType == .interest,
           let editingAsset = transactionToEdit?.asset,
           let editingAssetType = editingAsset.assetType,
           interestAssetTypes.contains(editingAssetType),
           let editingInstitution = transactionToEdit?.institution {
            let securitySelection = InterestSourceSelection.security(editingAsset.objectID)
            if !options.contains(where: { $0.selection == securitySelection }) {
                let displayName = editingAsset.symbol ?? editingAsset.name ?? "Security"
                options.append(
                    InterestSourceOption(
                        selection: securitySelection,
                        title: displayName,
                        assetID: editingAsset.objectID,
                        institutionID: editingInstitution.objectID
                    )
                )
            }
        }

        return options
    }

    private func interestSourceOption(for selection: InterestSourceSelection) -> InterestSourceOption? {
        interestSourceOptions.first { $0.selection == selection }
    }

    private var sellSourceAssets: [Asset] {
        // If no institution is selected, return empty array to disable security selection
        guard let institution = activeInstitutionSelection else {
            return []
        }

        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        var seen = Set<NSManagedObjectID>()
        var assets: [Asset] = []

        for holding in holdings {
            guard holding.quantity > 0 else { continue }
            guard let holdingInstitution = currentInstitution(of: holding),
                  holdingInstitution.objectID == institution.objectID else { continue }
            guard let asset = holding.asset else { continue }
            if !seen.contains(asset.objectID) {
                seen.insert(asset.objectID)
                assets.append(asset)
            }
        }

        return assets.sorted { ($0.symbol ?? $0.name ?? "") < ($1.symbol ?? $1.name ?? "") }
    }

    private var sellQuantityHint: String? {
        guard let maxQuantity = maxSellQuantity else { return nil }
        let formatted = Formatters.decimal(maxQuantity, fractionDigits: 5)
        return "(max: \(formatted))"
    }

    private var maxSellQuantity: Double? {
        guard selectedTransactionType == .sell,
              let sellAssetID = selectedSellAssetID,
              let sellAsset = try? viewContext.existingObject(with: sellAssetID) as? Asset else {
            return nil
        }

        let institution = activeInstitutionSelection
        let holding = holdingForAsset(sellAsset, institution: institution) ?? holdingForAsset(sellAsset, institution: nil)
        var availableQuantity = holding?.quantity ?? 0

        if let existingTransaction = transactionToEdit,
           let existingType = TransactionType(rawValue: existingTransaction.type ?? ""),
           existingType == .sell,
           existingTransaction.asset?.objectID == sellAsset.objectID {

            let txnInstitution = existingTransaction.value(forKey: "institution") as? Institution

            let matchesInstitution: Bool
            if let institution {
                matchesInstitution = txnInstitution?.objectID == institution.objectID
            } else {
                matchesInstitution = txnInstitution == nil
            }

            if matchesInstitution {
                availableQuantity += existingTransaction.quantity
            }
        }

        return availableQuantity
    }

    private func validateSellQuantity() {
        guard selectedTransactionType == .sell else {
            quantityValidationError = nil
            return
        }

        guard let maxQuantity = maxSellQuantity else {
            quantityValidationError = nil
            return
        }

        if quantity > maxQuantity {
            let formatted = Formatters.decimal(maxQuantity, fractionDigits: 5)
            quantityValidationError = "Quantity cannot exceed \(formatted) shares available"
        } else {
            quantityValidationError = nil
        }
    }

    @ViewBuilder
    private var assetInformationSection: some View {
        if selectedTransactionType == .sell {
            Section(header: Text("Security to Sell"), footer: Text("Select the security you want to sell.")) {
                if sellSourceAssets.isEmpty {
                    Text("No securities available to sell at this institution.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Picker("Security", selection: $selectedSellAssetID) {
                        Text("Select Security").tag(Optional<NSManagedObjectID>.none)
                        ForEach(sellSourceAssets, id: \.objectID) { asset in
                            Text(asset.symbol ?? asset.name ?? "Unknown")
                                .tag(Optional(asset.objectID))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
        } else if selectedTransactionType != .dividend && selectedTransactionType != .interest && selectedTransactionType != .deposit && selectedTransactionType != .insurance {
            Section(header: Text("Asset Information")) {
                Picker("Asset Type", selection: $selectedAssetType) {
                    ForEach(AssetType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                TextField("Symbol (e.g., AAPL)", text: $assetSymbol)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Name (optional)", text: $assetName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }

    @ViewBuilder
    private var transactionDetailsSection: some View {
        Section(header: Text("Transaction Details")) {
            DatePicker("Date", selection: $transactionDate, displayedComponents: .date)

            if selectedTransactionType == .deposit {
                Picker("Symbol", selection: $selectedDepositCategory) {
                    ForEach(DepositCategory.allCases, id: \.self) { category in
                        Text(category.displayTitle).tag(category)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                HStack {
                    Text("Interest Rate")
                    Spacer()
                    TextField("0", value: $depositInterestRate, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text("%")
                        .foregroundColor(.secondary)
                }
            } else if isStructuredProductTransaction {
                TextField("Linked Assets", text: $structuredProductLinkedAssets)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("0", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                }

                HStack {
                    Text("Price per Share")
                    Spacer()
                    TextField("0.00", value: $price, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text(selectedCurrency.symbol)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Investment Amount")
                    Spacer()
                    Text(Formatters.currency(quantity * price, symbol: selectedCurrency.symbol))
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Interest Rate")
                    Spacer()
                    TextField("0", value: $structuredProductInterestRate, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text("%")
                        .foregroundColor(.secondary)
                }
            }

            // Maturity date only for non-insurance transactions
            if selectedTransactionType != .insurance,
               selectedTransactionType != .sell,
               selectedTransactionType != .dividend,
               selectedTransactionType != .interest {
                Toggle("Set Maturity Date", isOn: $hasMaturityDate.animation())
                    .disabled(isMaturityToggleDisabled)
                if hasMaturityDate {
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                }
            }

            if isAmountOnly {
                if selectedTransactionType == .insurance {
                    // Cash Value for insurance transactions
                    HStack {
                        Text("Cash Value")
                        Spacer()
                        TextField("0.00", value: $cashValue, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(selectedCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Amount for other transaction types
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(selectedCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                }
            } else if isStructuredProductTransaction {
                Toggle("Auto-fetch price from Yahoo Finance", isOn: $autoFetchPrice)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if selectedTransactionType == .sell && sellQuantityHint != nil {
                            HStack(spacing: 4) {
                                Text("Quantity \(sellQuantityHint!)")
                                Button(">>") {
                                    if let maxQuantity = maxSellQuantity {
                                        quantity = maxQuantity
                                    }
                                }
                                .foregroundColor(.blue)
                                .font(.caption)
                            }
                        } else {
                            Text("Quantity")
                        }
                        Spacer()
                        TextField("0", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                            .onChange(of: quantity) { _, _ in
                                validateSellQuantity()
                            }
                    }

                    if let error = quantityValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }

                HStack {
                    Text("Price per Share")
                    Spacer()
                    TextField("0.00", value: $price, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text(selectedCurrency.symbol)
                        .foregroundColor(.secondary)
                }

                if selectedTransactionType == .sell {
                    HStack {
                        Text("Accrued Interest")
                        Spacer()
                        TextField("0.00", value: $accruedInterest, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Text(selectedCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Total Value")
                    Spacer()
                    Text(Formatters.currency(selectedTransactionType == .sell ? (quantity * price + accruedInterest) : (quantity * price), symbol: selectedCurrency.symbol))
                        .fontWeight(.medium)
                }

                if selectedTransactionType == .buy {
                    Toggle("Auto-fetch price from Yahoo Finance", isOn: $autoFetchPrice)
                }
            }

            // Fees only for non-insurance transactions
            if selectedTransactionType != .insurance {
                HStack {
                    Text("Fees")
                    Spacer()
                    TextField("0.00", value: $fees, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text(selectedCurrency.symbol)
                        .foregroundColor(.secondary)
                }

                if selectedTransactionType == .buy {
                    HStack {
                        Text("Settlement Amount")
                        Spacer()
                        Text(Formatters.currency(settlementAmountForDisplay, symbol: selectedCurrency.symbol))
                            .fontWeight(.semibold)
                    }
                }
            }

            if requiresTax {
                HStack {
                    Text("Tax")
                    Spacer()
                    TextField("0.00", value: $tax, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 120)
                    Text(selectedCurrency.symbol)
                        .foregroundColor(.secondary)
                }
            }

            if selectedTransactionType == .dividend || selectedTransactionType == .interest {
                HStack {
                    Text("Settlement Amount")
                    Spacer()
                    Text(Formatters.currency(incomeSettlementAmountForDisplay, symbol: selectedCurrency.symbol))
                        .fontWeight(.semibold)
                }
            }
            
            if selectedTransactionType == .sell {
                HStack {
                    Text("Settlement Amount")
                    Spacer()
                    Text(Formatters.currency(sellSettlementAmountForDisplay, symbol: selectedCurrency.symbol))
                        .fontWeight(.semibold)
                }
            }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private func findExistingInstitution(name: String) -> Institution? {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name.trimmingCharacters(in: .whitespacesAndNewlines))
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func fetchDepositAsset(for category: DepositCategory) -> Asset? {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, category.assetSymbol)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }


    private func manageCashDisciplineCompanion(for transaction: Transaction) {
        let epsilon = 1e-6
        let cashDisciplineEnabled = portfolio.enforcesCashDisciplineEnabled
        guard cashDisciplineEnabled,
              let typeRaw = transaction.type,
              let type = TransactionType(rawValue: typeRaw),
              (type == .buy || type == .sell || type == .insurance) else {
            removeCashDisciplineCompanion(for: transaction)
            return
        }

        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency

        let institution: Institution?
        switch type {
        case .insurance:
            institution = resolvePaymentInstitution(for: transaction)
        default:
            institution = transaction.institution
        }

        guard let institution else {
            removeCashDisciplineCompanion(for: transaction)
            return
        }

        switch type {
        case .buy:
            let totalCost = (transaction.quantity * transaction.price) + transaction.fees + transaction.tax
            if abs(totalCost) < epsilon {
                removeCashDisciplineCompanion(for: transaction)
                return
            }
            upsertCashDisciplineCompanion(for: transaction, amount: -totalCost, currency: transactionCurrency, institution: institution)
        case .sell:
            let netProceeds = transaction.amount - transaction.fees - transaction.tax
            if abs(netProceeds) < epsilon {
                removeCashDisciplineCompanion(for: transaction)
                return
            }
            upsertCashDisciplineCompanion(for: transaction, amount: netProceeds, currency: transactionCurrency, institution: institution)
        case .insurance:
            let premiumAmount = initialInsurancePaymentAmount()
            if abs(premiumAmount) < epsilon {
                removeCashDisciplineCompanion(for: transaction)
                return
            }
            upsertCashDisciplineCompanion(for: transaction, amount: -premiumAmount, currency: transactionCurrency, institution: institution)
        default:
            removeCashDisciplineCompanion(for: transaction)
        }
    }

    private func upsertCashDisciplineCompanion(for transaction: Transaction, amount: Double, currency: Currency, institution: Institution) {
        let epsilon = 1e-6
        guard abs(amount) > epsilon else {
            removeCashDisciplineCompanion(for: transaction)
            return
        }

        guard let companionNote = CashDisciplineService.companionNote(for: transaction, companionAmount: amount, currency: currency) else {
            removeCashDisciplineCompanion(for: transaction)
            return
        }

        let existingCompanion = CashDisciplineService.findCompanionDeposit(for: transaction, in: viewContext)
        let depositAsset = findOrCreateDepositAsset(for: .demand, existingAsset: existingCompanion?.asset)
        let transactionDate = transaction.transactionDate ?? Date()

        if let companion = existingCompanion {
            TransactionImpactService.reverse(companion, in: portfolio, context: viewContext)
            companion.transactionDate = transactionDate
            companion.amount = amount
            companion.price = amount
            companion.quantity = 1
            companion.fees = 0
            companion.tax = 0
            companion.currency = currency.rawValue
            companion.notes = companionNote
            companion.type = TransactionType.deposit.rawValue
            companion.autoFetchPrice = false
            if let name = institution.name, !name.isEmpty {
                companion.tradingInstitution = name
            } else {
                companion.tradingInstitution = nil
            }
            companion.institution = institution
            companion.portfolio = portfolio
            companion.asset = depositAsset
            companion.ensureIdentifiers()
        } else {
            let companion = Transaction(context: viewContext)
            companion.transactionDate = transactionDate
            companion.type = TransactionType.deposit.rawValue
            companion.currency = currency.rawValue
            companion.amount = amount
            companion.price = amount
            companion.quantity = 1
            companion.fees = 0
            companion.tax = 0
            companion.notes = companionNote
            companion.autoFetchPrice = false
            if let name = institution.name, !name.isEmpty {
                companion.tradingInstitution = name
            }
            companion.institution = institution
            companion.portfolio = portfolio
            companion.asset = depositAsset
            companion.createdAt = Date()
            companion.ensureIdentifiers()
        }

        maintainInstitutionAssetRelationship(institution: institution, asset: depositAsset, transactionDate: transactionDate)
        applyCashDisciplineDepositImpact(amount: amount, currency: currency, institution: institution)
    }

    private func applyCashDisciplineDepositImpact(amount: Double, currency: Currency, institution: Institution) {
        guard abs(amount) > 1e-6 else { return }
        let converted = convertToPortfolioCurrency(amount, from: currency)
        institution.addToCashBalance(for: portfolio, currency: currency, delta: amount)
        portfolio.addToCash(converted)
    }

    private func removeCashDisciplineCompanion(for transaction: Transaction) {
        guard let companion = CashDisciplineService.findCompanionDeposit(for: transaction, in: viewContext) else { return }
        TransactionImpactService.reverse(companion, in: portfolio, context: viewContext)
        viewContext.delete(companion)
    }

    private func validateIncomeCurrency(for asset: Asset, currency: Currency) -> String? {
        guard let transactions = asset.transactions?.allObjects as? [Transaction] else { return nil }
        let relevantBuys = transactions.filter { txn in
            txn.portfolio?.objectID == portfolio.objectID &&
            txn.type == TransactionType.buy.rawValue
        }

        let currencyCodes = Set(relevantBuys.compactMap { txn in
            txn.currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })

        if currencyCodes.count > 1 {
            return "Dividends and interest can only be recorded for holdings purchased in a single currency. Please consolidate the holding before recording income."
        }

        if let expectedCode = currencyCodes.first,
           expectedCode != currency.rawValue {
            return "Use \(expectedCode) for dividends and interest to match the holding's purchase currency."
        }

        return nil
    }

    private func holdingForAsset(_ asset: Asset, institution: Institution?) -> Holding? {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        if let institution {
            return holdings.first {
                $0.asset?.objectID == asset.objectID &&
                currentInstitution(of: $0)?.objectID == institution.objectID
            }
        } else {
            return holdings.first {
                $0.asset?.objectID == asset.objectID &&
                currentInstitution(of: $0) == nil
            }
        }
    }

    private func validateHoldingInstitution(for asset: Asset, institution: Institution?) -> String? {
        let holdings = (portfolio.holdings?.allObjects as? [Holding])?.filter { $0.asset?.objectID == asset.objectID } ?? []

        guard !holdings.isEmpty else { return nil }

        if let institution {
            if let conflicting = holdings.first(where: { holding in
                guard holding.quantity > 0 else { return false }
                if let holdingInstitution = currentInstitution(of: holding) {
                    return holdingInstitution.objectID != institution.objectID
                }
                return false
            }) {
                let institutionName = currentInstitution(of: conflicting)?.name ?? "another institution"
                return "This holding is tracked under \(institutionName). Select that institution to continue."
            }
        } else if let assigned = holdings.first(where: { holding in
            holding.quantity > 0 && currentInstitution(of: holding) != nil
        }) {
            let institutionName = currentInstitution(of: assigned)?.name ?? "an institution"
            return "This holding is tracked under \(institutionName). Choose that institution to continue."
        }

        return nil
    }

    private func recordIncome(for asset: Asset, netAmount: Double, transactionCurrency: Currency, institution: Institution?) {
        guard let holding = holdingForAsset(asset, institution: institution) ?? holdingForAsset(asset, institution: nil) else { return }
        let incomeInPortfolioCurrency = convertToPortfolioCurrency(netAmount, from: transactionCurrency)
        holding.totalDividends += incomeInPortfolioCurrency
        holding.updatedAt = Date()
    }

    private func currentInstitution(of holding: Holding) -> Institution? {
        holding.value(forKey: "institution") as? Institution
    }

    private func assignInstitution(_ institution: Institution?, to holding: Holding) {
        holding.setValue(institution, forKey: "institution")
    }

    private func recomputePortfolioTotals() {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let totalHoldings = holdings.reduce(0.0) { partial, holding in
            guard let asset = holding.asset else { return partial }
            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return partial + cashValue
            }
            return partial + (holding.quantity * asset.currentPrice)
        }
        portfolio.totalValue = totalHoldings + portfolio.resolvedCashBalance()
        portfolio.updatedAt = Date()
    }
    
    private func convertToPortfolioCurrency(_ amount: Double, from currency: Currency) -> Double {
        currencyService.convertAmount(amount, from: currency, to: portfolioCurrency)
    }

    private func resolvePaymentInstitution(for transaction: Transaction) -> Institution? {
        if let selectedPaymentInstitution {
            return selectedPaymentInstitution
        }

        if let name = transaction.value(forKey: "paymentInstitutionName") as? String,
           let resolved = fetchInstitution(named: name) {
            return resolved
        }

        return transaction.institution
    }

    private func fetchInstitution(named name: String) -> Institution? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmed)
        request.fetchLimit = 1

        return try? viewContext.fetch(request).first
    }

    private func findOrCreateInstitution(name: String) -> (Institution, Bool) {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)

        if let existingInstitution = try? viewContext.fetch(request).first {
            return (existingInstitution, false)
        } else {
            let newInstitution = Institution(context: viewContext)
            newInstitution.id = UUID()
            newInstitution.name = name
            newInstitution.createdAt = Date()
            let defaultCurrency = Currency(rawValue: portfolio.mainCurrency ?? Currency.usd.rawValue) ?? .usd
            newInstitution.setCashBalance(for: portfolio, currency: defaultCurrency, amount: 0)
            return (newInstitution, true)
        }
    }

    private func findOrCreateDepositAsset(for category: DepositCategory, existingAsset: Asset?) -> Asset {
        if let asset = existingAsset, asset.assetType == AssetType.deposit.rawValue {
            let currentSymbol = asset.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let targetSymbol = category.assetSymbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if currentSymbol == targetSymbol {
                asset.lastPriceUpdate = Date()
                return asset
            }
        }

        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, category.assetSymbol)

        if let existingAsset = try? viewContext.fetch(request).first {
            existingAsset.symbol = category.assetSymbol
            existingAsset.name = category.assetName
            existingAsset.assetType = AssetType.deposit.rawValue
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

    private func configureStructuredProductAsset(_ asset: Asset) {
        asset.assetType = AssetType.structuredProduct.rawValue
        asset.setValue(structuredProductInterestRate, forKey: "interestRate")
        let trimmedLinked = structuredProductLinkedAssets.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.setValue(trimmedLinked.isEmpty ? nil : trimmedLinked, forKey: "linkedAssets")
        let convertedValue = convertToPortfolioCurrency(price, from: selectedCurrency)
        asset.currentPrice = convertedValue
        asset.lastPriceUpdate = Date()
    }

    private func findOrCreateAsset() -> Asset {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "symbol == %@", assetSymbol.uppercased())
        
        if let existingAsset = try? viewContext.fetch(request).first {
            existingAsset.assetType = selectedAssetType.rawValue
            if !assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existingAsset.name = assetName
            }
            existingAsset.symbol = assetSymbol.uppercased()
            return existingAsset
        } else {
            let newAsset = Asset(context: viewContext)
            newAsset.id = UUID()
            newAsset.symbol = assetSymbol.uppercased()
            newAsset.name = assetName.isEmpty ? assetSymbol.uppercased() : assetName
            newAsset.assetType = selectedAssetType.rawValue
            newAsset.createdAt = Date()
            let convertedPrice = convertToPortfolioCurrency(price, from: selectedCurrency)
            newAsset.currentPrice = convertedPrice
            newAsset.lastPriceUpdate = Date()
            return newAsset
        }
    }
    
    private func updateHolding(for asset: Asset, transaction: Transaction) -> Double? {
        let request: NSFetchRequest<Holding> = Holding.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", asset, portfolio)
        let transactionInstitution = transaction.institution

        let existingHoldings = (try? viewContext.fetch(request)) ?? []

        let holding: Holding
        if let txnInstitution = transactionInstitution {
            if let matched = existingHoldings.first(where: { currentInstitution(of: $0)?.objectID == txnInstitution.objectID }) {
                holding = matched
            } else if let unassigned = existingHoldings.first(where: { currentInstitution(of: $0) == nil }) {
                assignInstitution(txnInstitution, to: unassigned)
                holding = unassigned
            } else if let firstExisting = existingHoldings.first {
                holding = firstExisting
            } else {
                holding = Holding(context: viewContext)
                holding.id = UUID()
                holding.asset = asset
                holding.portfolio = portfolio
                holding.quantity = 0
                holding.averageCostBasis = 0
                holding.realizedGainLoss = 0
                holding.totalDividends = 0
                assignInstitution(txnInstitution, to: holding)
            }
        } else if let matched = existingHoldings.first(where: { currentInstitution(of: $0) == nil }) {
            holding = matched
        } else if let firstExisting = existingHoldings.first {
            holding = firstExisting
        } else {
            holding = Holding(context: viewContext)
            holding.id = UUID()
            holding.asset = asset
            holding.portfolio = portfolio
            holding.quantity = 0
            holding.averageCostBasis = 0
            holding.realizedGainLoss = 0
            holding.totalDividends = 0
        }
        
        if currentInstitution(of: holding) == nil, let txnInstitution = transactionInstitution {
            assignInstitution(txnInstitution, to: holding)
        }
        
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let quantity = transaction.quantity
        let priceInPortfolioCurrency = currencyService.convertAmount(transaction.price, from: transactionCurrency, to: portfolioCurrency)
        let amountInPortfolioCurrency = currencyService.convertAmount(transaction.amount, from: transactionCurrency, to: portfolioCurrency)

        guard let transactionType = TransactionType(rawValue: transaction.type ?? "") else { return nil }

        var realizedGainForTransaction: Double? = nil

        switch transactionType {
        case .buy:
            let currentCost = holding.quantity * holding.averageCostBasis
            let feesInPortfolio = currencyService.convertAmount(transaction.fees, from: transactionCurrency, to: portfolioCurrency)
            let taxInPortfolio = currencyService.convertAmount(transaction.tax, from: transactionCurrency, to: portfolioCurrency)
            let totalCost = (quantity * priceInPortfolioCurrency) + feesInPortfolio + taxInPortfolio
            let newTotalCost = currentCost + totalCost
            let newTotalQuantity = holding.quantity + quantity
            holding.averageCostBasis = newTotalQuantity > 0 ? newTotalCost / newTotalQuantity : 0
            holding.quantity = newTotalQuantity

        case .sell:
            let grossProceeds = quantity * priceInPortfolioCurrency
            let feesInPortfolio = currencyService.convertAmount(transaction.fees, from: transactionCurrency, to: portfolioCurrency)
            let taxInPortfolio = currencyService.convertAmount(transaction.tax, from: transactionCurrency, to: portfolioCurrency)
            let totalCost = quantity * holding.averageCostBasis
            let realizedGain = (grossProceeds - feesInPortfolio - taxInPortfolio) - totalCost
            holding.realizedGainLoss += realizedGain
            holding.quantity -= quantity
            if holding.quantity < 0 {
                holding.quantity = 0
            }
            if holding.quantity == 0 {
                holding.averageCostBasis = 0
            }
            realizedGainForTransaction = realizedGain
            
        case .dividend, .interest:
            holding.totalDividends += amountInPortfolioCurrency
        case .deposit, .insurance:
            // No holding changes for cash movements
            break
        }
        
        holding.updatedAt = Date()
        print("📈 Updated holding for \(asset.symbol ?? "Unknown"): qty=\(holding.quantity), cost=\(holding.averageCostBasis), dividends=\(holding.totalDividends)")
        return realizedGainForTransaction
    }

    private func createInsuranceAsset() -> Asset {
        let policyName = "\(insuranceType) - \(policyholder)"
        let trimmedSymbol = insuranceSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        if !trimmedSymbol.isEmpty {
            request.predicate = NSPredicate(format: "symbol ==[c] %@", trimmedSymbol)
        } else {
            request.predicate = NSPredicate(format: "name ==[c] %@", policyName)
        }

        if let existingAsset = try? viewContext.fetch(request).first {
            return existingAsset
        } else {
            let newAsset = Asset(context: viewContext)
            newAsset.id = UUID()
            newAsset.name = policyName
            newAsset.symbol = trimmedSymbol.isEmpty ? "INS-\(UUID().uuidString.prefix(8))" : trimmedSymbol
            newAsset.assetType = AssetType.insurance.rawValue
            newAsset.currentPrice = 1.0 // Insurance policies don't have market prices
            newAsset.createdAt = Date()
            newAsset.lastPriceUpdate = Date()
            return newAsset
        }
    }

    private func updateInsuranceHolding(for asset: Asset, transaction: Transaction) {
        let request: NSFetchRequest<Holding> = Holding.fetchRequest()
        request.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", asset, portfolio)

        let holding: Holding
        if let existingHolding = try? viewContext.fetch(request).first {
            holding = existingHolding
        } else {
            holding = Holding(context: viewContext)
            holding.id = UUID()
            holding.asset = asset
            holding.portfolio = portfolio
            holding.quantity = 1 // Insurance policies typically have quantity of 1
            holding.averageCostBasis = 0
            holding.realizedGainLoss = 0
            holding.totalDividends = 0
        }

        // Set the cash value
        let convertedCashValue = convertToPortfolioCurrency(cashValue, from: selectedCurrency)
        holding.setValue(convertedCashValue, forKey: "cashValue")

        holding.updatedAt = Date()
        print("🛡️ Updated insurance holding: \(asset.name ?? "Unknown"), cash value: \(convertedCashValue)")
    }
}

struct BeneficiaryData: Identifiable {
    let id = UUID()
    var name: String
    var percentage: Double
}

enum DepositCategory: String, CaseIterable {
    case demand = "demand deposit"
    case fixed = "fixed deposit"

    var displayTitle: String {
        rawValue.capitalized
    }

    var assetSymbol: String {
        displayTitle
    }

    var assetName: String {
        displayTitle
    }

    static func resolve(from value: String?) -> DepositCategory? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !normalized.isEmpty else {
            return nil
        }
        return DepositCategory(rawValue: normalized)
    }
}

fileprivate enum InterestSourceSelection: Hashable {
    case demand
    case fixedDeposit(NSManagedObjectID)
    case security(NSManagedObjectID)

    var identifier: String {
        switch self {
        case .demand:
            return "demand"
        case .fixedDeposit(let objectID):
            return "fixed-\(objectID.uriRepresentation().absoluteString)"
        case .security(let objectID):
            return "security-\(objectID.uriRepresentation().absoluteString)"
        }
    }
}

fileprivate struct InterestSourceOption: Identifiable, Hashable {
    let selection: InterestSourceSelection
    let title: String
    let assetID: NSManagedObjectID?
    let institutionID: NSManagedObjectID?

    var id: String { selection.identifier }
}

private extension AddTransactionView {
    func insurancePaymentRawAmount() -> Double {
        initialInsurancePaymentAmount()
    }

    func initialInsurancePaymentAmount() -> Double {
        if firstDiscountedPremium > 0 {
            return firstDiscountedPremium
        }

        let normalized = premiumPaymentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "lump sum" {
            if totalPremium > 0 {
                return totalPremium
            }
            if singlePremium > 0 {
                let term = max(1, Int(premiumPaymentTerm))
                return singlePremium * Double(term)
            }
            return 0
        }

        if premiumPaymentTerm <= 1 {
            if totalPremium > 0 {
                return totalPremium
            }
        }

        return singlePremium
    }

    func calculateTotalPremium() {
        let termCount = max(0, Double(premiumPaymentTerm))

        if termCount <= 0 {
            if firstDiscountedPremium > 0 {
                totalPremium = firstDiscountedPremium
            } else {
                totalPremium = singlePremium
            }
            return
        }

        if firstDiscountedPremium > 0 {
            let remainingTermCount = max(0, termCount - 1)
            totalPremium = firstDiscountedPremium + remainingTermCount * singlePremium
        } else {
            totalPremium = singlePremium * termCount
        }
    }

    func maintainInstitutionAssetRelationship(institution: Institution, asset: Asset, transactionDate: Date) {
        // Check if relationship already exists
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@ AND asset == %@", institution, asset)
        request.fetchLimit = 1

        do {
            let existingRelationships = try viewContext.fetch(request)

            if let existingRelationship = existingRelationships.first {
                // Update the last transaction date
                existingRelationship.setValue(transactionDate, forKey: "lastTransactionDate")
                print("🔗 Updated existing Institution-Asset relationship: \(institution.name ?? "Unknown") <-> \(asset.symbol ?? "Unknown")")
            } else {
                // Create new relationship
                let availability = NSEntityDescription.insertNewObject(forEntityName: "InstitutionAssetAvailability", into: viewContext)
                availability.setValue(UUID(), forKey: "id")
                availability.setValue(Date(), forKey: "createdAt")
                availability.setValue(transactionDate, forKey: "lastTransactionDate")
                availability.setValue(institution, forKey: "institution")
                availability.setValue(asset, forKey: "asset")
                print("🆕 Created new Institution-Asset relationship: \(institution.name ?? "Unknown") <-> \(asset.symbol ?? "Unknown")")
            }
        } catch {
            print("❌ Error maintaining Institution-Asset relationship: \(error)")
        }
    }

    func getAssetsAvailableAt(institution: Institution) -> [Asset] {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@", institution)
        request.sortDescriptors = [NSSortDescriptor(key: "lastTransactionDate", ascending: false)]

        do {
            let availabilities = try viewContext.fetch(request)
            return availabilities.compactMap { $0.value(forKey: "asset") as? Asset }
        } catch {
            print("❌ Error fetching assets for institution \(institution.name ?? "Unknown"): \(error)")
            return []
        }
    }
}

extension Asset {
    var resolvedAutoFetchPreference: Bool {
        let override = value(forKey: "autoFetchPriceEnabled") as? Bool
        let allTransactions = transactions?.allObjects as? [Transaction] ?? []
        let transactionDrivenPreference: Bool = {
            guard !allTransactions.isEmpty else { return true }
            return allTransactions.contains { $0.autoFetchPrice }
        }()

        if let override {
            if override && !transactionDrivenPreference && !allTransactions.isEmpty {
                // Stored value likely comes from legacy default; honor live transaction setting instead.
                return transactionDrivenPreference
            }
            return override
        }

        return transactionDrivenPreference
    }

    func applyAutoFetchPreference(_ enabled: Bool, limitTo portfolio: Portfolio? = nil) {
        setValue(enabled, forKey: "autoFetchPriceEnabled")

        guard let allTransactions = transactions?.allObjects as? [Transaction] else { return }
        for transaction in allTransactions {
            if let portfolio,
               let transactionPortfolio = transaction.portfolio,
               transactionPortfolio.objectID != portfolio.objectID {
                continue
            }
            if transaction.autoFetchPrice != enabled {
                transaction.autoFetchPrice = enabled
            }
        }
    }
}

#Preview {
    AddTransactionView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
