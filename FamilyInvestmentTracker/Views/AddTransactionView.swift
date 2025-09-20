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
    // Dividend-specific: source security
    @State private var selectedDividendAssetID: NSManagedObjectID?
    // Sell-specific: security to sell
    @State private var selectedSellAssetID: NSManagedObjectID?
    // Deposit-specific selection
    @State private var selectedDepositCategory = DepositCategory.demand
    @State private var depositInterestRate: Double = 0

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
        _transactionDate = State(initialValue: transactionToEdit?.transactionDate ?? defaultDate)
        _notes = State(initialValue: transactionToEdit?.notes ?? "")
        _amount = State(initialValue: transactionToEdit?.amount ?? 0)
        _tradingInstitution = State(initialValue: transactionToEdit?.tradingInstitution ?? "")
        _selectedInstitution = State(initialValue: transactionToEdit?.institution)
        let shouldUseCustomInstitution = transactionToEdit?.institution == nil && !(transactionToEdit?.tradingInstitution?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
            let existingRate = transactionToEdit?.asset?.value(forKey: "interestRate") as? Double
            initialInterestRate = existingRate ?? 0
        } else {
            initialInterestRate = 0
        }
        _depositInterestRate = State(initialValue: initialInterestRate)

        let hasMaturity = (transactionToEdit?.maturityDate != nil) && (initialType != .deposit || initialDepositCategory == .fixed)
        _hasMaturityDate = State(initialValue: hasMaturity)
        _maturityDate = State(initialValue: transactionToEdit?.maturityDate ?? defaultDate)
        _autoFetchPrice = State(initialValue: transactionToEdit?.autoFetchPrice ?? true)

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

    private var availableInstitutions: [Institution] {
        institutions.compactMap { institution in
            guard let name = institution.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return institution
        }
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
                if selectedTransactionType == .buy {
                    Section(header: Text("Asset Information")) {
                        Picker("Asset Type", selection: $selectedAssetType) {
                            ForEach(AssetType.allCases.filter { $0 != .deposit && $0 != .insurance }, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                
                        TextField("Symbol (e.g., AAPL)", text: $assetSymbol)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.characters)
                        
                        TextField("Asset Name", text: $assetName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                } else if selectedTransactionType == .sell {
                    let hasInstitution = selectedInstitution != nil || !tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let footerText = hasInstitution ? "Select the holding you want to sell." : "Select a trading institution first to see available securities."

                    Section(header: Text("Sell Security"), footer: Text(footerText)) {
                        Picker("Security", selection: $selectedSellAssetID) {
                            if hasInstitution {
                                Text("Select...").tag(Optional<NSManagedObjectID>.none)
                                ForEach(sellSourceAssets, id: \.objectID) { asset in
                                    Text(asset.symbol ?? asset.name ?? "Unknown")
                                        .tag(Optional(asset.objectID))
                                }
                            } else {
                                Text("Select institution first").tag(Optional<NSManagedObjectID>.none)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .disabled(!hasInstitution)
                    }
                }
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
                
                // Transaction Details
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
                    }

                    // Maturity date only for non-insurance transactions
                    if selectedTransactionType != .insurance {
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
                    } else {
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
                            Text("Total Value")
                            Spacer()
                            Text(Formatters.currency(quantity * price, symbol: selectedCurrency.symbol))
                                .fontWeight(.medium)
                        }

                        Toggle("Auto-fetch price from Yahoo Finance", isOn: $autoFetchPrice)
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
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

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
                            Text(selectedCurrency.symbol)
                                .foregroundColor(.secondary)
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

                        HStack {
                            Text("Payment Term (Years)")
                            Spacer()
                            TextField("0", value: $premiumPaymentTerm, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
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
                        Toggle("Has Supplementary Insurance", isOn: $hasSupplementaryInsurance)
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
            switch newValue {
            case .dividend:
                if selectedDividendAssetID == nil { selectedDividendAssetID = dividendSourceAssets.first?.objectID }
                selectedSellAssetID = nil
            case .sell:
                if selectedSellAssetID == nil { selectedSellAssetID = sellSourceAssets.first?.objectID }
                selectedDividendAssetID = nil
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
            default:
                selectedDividendAssetID = nil
                selectedSellAssetID = nil
                selectedPaymentInstitution = nil
            }

            if newValue == .deposit && selectedDepositCategory != .fixed {
                hasMaturityDate = false
            }
        }
        .onAppear {
            if selectedTransactionType == .insurance && selectedPaymentInstitution == nil {
                selectedPaymentInstitution = selectedInstitution
            }
        }
        .onChange(of: selectedInstitution) { _, newValue in
            if selectedTransactionType == .insurance && selectedPaymentInstitution == nil {
                selectedPaymentInstitution = newValue
            }

            // Reset selected sell asset when institution changes for sell transactions
            if selectedTransactionType == .sell {
                selectedSellAssetID = nil
            }
        }
        .onChange(of: tradingInstitution) { _, newValue in
            // Reset selected sell asset when trading institution text changes for sell transactions
            if selectedTransactionType == .sell {
                selectedSellAssetID = nil
            }
        }
        .onChange(of: selectedDepositCategory) { _, newValue in
            if selectedTransactionType == .deposit && newValue != .fixed {
                hasMaturityDate = false
            }
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
        switch selectedTransactionType {
        case .dividend, .interest:
            return amount > 0 && hasValidInstitution
        case .sell:
            return selectedSellAssetID != nil && quantity > 0 && price > 0 && hasValidInstitution
        case .buy:
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

        if selectedTransactionType == .sell {
            guard let sellID = selectedSellAssetID,
                  let sellAsset = try? viewContext.existingObject(with: sellID) as? Asset else {
                failWithMessage("Select a holding to sell before saving.")
                return
            }

            let holdingFetch: NSFetchRequest<Holding> = Holding.fetchRequest()
            holdingFetch.predicate = NSPredicate(format: "asset == %@ AND portfolio == %@", sellAsset, portfolio)
            holdingFetch.fetchLimit = 1

            let availableQuantity = (try? viewContext.fetch(holdingFetch).first?.quantity) ?? 0
            let previousQuantity = (existingTransactionType == .sell && existingTransaction?.asset?.objectID == sellAsset.objectID) ? (existingTransaction?.quantity ?? 0) : 0
            if availableQuantity + previousQuantity + 1e-6 < quantity {
                failWithMessage("Not enough shares available to sell. You currently hold \(Formatters.decimal(availableQuantity + previousQuantity)).")
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
                let requiredFundsTransactionCurrency = (quantity * price) + fees + tax
                let requiredFunds = max(0, convertToPortfolioCurrency(requiredFundsTransactionCurrency, from: selectedCurrency))
                var availableFunds = institution.cashBalanceSafe
                if let existingTransaction,
                   existingTransactionType == .buy,
                   existingTransaction.institution == institution {
                    let previousCurrency = Currency(rawValue: existingTransaction.currency ?? selectedCurrency.rawValue) ?? selectedCurrency
                    let previousCostRaw = (existingTransaction.quantity * existingTransaction.price) + existingTransaction.fees + existingTransaction.tax
                    let previousCost = convertToPortfolioCurrency(previousCostRaw, from: previousCurrency)
                    availableFunds += previousCost
                }
                if availableFunds + 1e-6 < requiredFunds {
                    failWithMessage("Not enough cash in \(institution.name ?? "this institution") to complete this purchase. If you do not want cash to be deducted at the time of purchase, you can go to the portfolio settings to turn off 'Enforce Cash Discipline'.")
                    return
                }
            case .insurance:
                let paymentInstitution = selectedPaymentInstitution ?? institutionForTransaction
                guard let paymentInstitution = paymentInstitution else {
                    failWithMessage("Select a payment institution for this insurance policy.")
                    return
                }
                let premiumAmount = max(0, insurancePaymentRawAmount())
                let requiredFunds = max(0, convertToPortfolioCurrency(premiumAmount, from: selectedCurrency))
                var availableFunds = paymentInstitution.cashBalanceSafe
                if let existingTransaction,
                   existingTransactionType == .insurance {
                    let previousInstitutionName = existingTransaction.value(forKey: "paymentInstitutionName") as? String ?? existingTransaction.institution?.name
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
                    if institution.cashBalanceSafe < convertedWithdrawal {
                        let institutionName = institution.name ?? "this institution"
                        let currentBalance = currencyService.formatAmount(institution.cashBalanceSafe, in: portfolioCurrency)
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
        transaction.setValue(false, forKey: "paymentDeducted")
        transaction.setValue(0.0, forKey: "paymentDeductedAmount")
        transaction.realizedGainAmount = 0
        transaction.asset = nil

        if isAmountOnly {
            if selectedTransactionType == .insurance {
                transaction.amount = cashValue
                transaction.quantity = 1
                transaction.price = cashValue

                if cashDisciplineEnabled {
                    let premiumAmount = max(0, insurancePaymentRawAmount())
                    let convertedPremium = convertToPortfolioCurrency(premiumAmount, from: selectedCurrency)
                    if convertedPremium > 0, let paymentInstitution = resolvedPaymentInstitution {
                        portfolio.addToCash(-convertedPremium)
                        paymentInstitution.cashBalanceSafe -= convertedPremium
                        transaction.setValue(true, forKey: "paymentDeducted")
                        transaction.setValue(convertedPremium, forKey: "paymentDeductedAmount")
                        transaction.setValue(paymentInstitution.name, forKey: "paymentInstitutionName")
                    } else {
                        transaction.setValue(false, forKey: "paymentDeducted")
                        transaction.setValue(0.0, forKey: "paymentDeductedAmount")
                    }
                }
            } else {
                transaction.amount = amount
                transaction.quantity = 1
                transaction.price = amount

                if selectedTransactionType == .deposit {
                    let depositAsset = findOrCreateDepositAsset(for: selectedDepositCategory, existingAsset: previousAsset)
                    transaction.asset = depositAsset
                }

                let netCash = amount - fees - tax
                switch selectedTransactionType {
                case .deposit:
                    // For deposits, allow negative amounts (withdrawals)
                    let convertedNetCash = convertToPortfolioCurrency(netCash, from: selectedCurrency)

                    // Always update institution cash for deposits since our dashboard shows institution cash totals
                    if let institution = institutionForTransaction {
                        institution.cashBalanceSafe += convertedNetCash
                    }
                    portfolio.addToCash(convertedNetCash)
                case .dividend:
                    // For dividends, ensure non-negative amounts
                    let convertedNetCash = max(0, convertToPortfolioCurrency(netCash, from: selectedCurrency))

                    // Update institution cash if available, otherwise portfolio cash
                    if let institution = institutionForTransaction {
                        institution.cashBalanceSafe += convertedNetCash
                    } else {
                        portfolio.addToCash(convertedNetCash)
                    }

                    if let assetID = selectedDividendAssetID,
                       let srcAsset = try? viewContext.existingObject(with: assetID) as? Asset {
                        transaction.asset = srcAsset

                        // Maintain institution-asset relationship for dividends
                        if let institution = institutionForTransaction {
                            maintainInstitutionAssetRelationship(institution: institution, asset: srcAsset, transactionDate: transactionDate)
                        }
                    }
                case .interest:
                    // For interest, ensure non-negative amounts
                    let convertedNetCash = max(0, convertToPortfolioCurrency(netCash, from: selectedCurrency))

                    // Update institution cash if available, otherwise portfolio cash
                    if let institution = institutionForTransaction {
                        institution.cashBalanceSafe += convertedNetCash
                    } else {
                        portfolio.addToCash(convertedNetCash)
                    }
                default:
                    break
                }
            }
        } else {
            transaction.quantity = quantity
            transaction.price = price
            transaction.amount = quantity * price

            let asset: Asset
            if selectedTransactionType == .sell, let preselectedSellAsset {
                asset = preselectedSellAsset
            } else {
                asset = findOrCreateAsset()
            }
            transaction.asset = asset

            // Maintain institution-asset relationship for buy/sell transactions
            if let institution = institutionForTransaction {
                maintainInstitutionAssetRelationship(institution: institution, asset: asset, transactionDate: transactionDate)
            }

            if let realizedGain = updateHolding(for: asset, transaction: transaction) {
                transaction.realizedGainAmount = realizedGain
            }

            if selectedTransactionType == .sell {
                let netProceeds = (quantity * price) - fees - tax
                if netProceeds != 0 {
                    let convertedProceeds = convertToPortfolioCurrency(netProceeds, from: selectedCurrency)

                    // Update institution cash if available, otherwise portfolio cash
                    if let institution = institutionForTransaction {
                        institution.cashBalanceSafe += convertedProceeds
                    } else {
                        portfolio.addToCash(convertedProceeds)
                    }
                }
            } else if selectedTransactionType == .buy {
                let requiredFundsTransactionCurrency = (quantity * price) + fees + tax
                let requiredFunds = max(0, convertToPortfolioCurrency(requiredFundsTransactionCurrency, from: selectedCurrency))

                // Update institution cash if available, otherwise portfolio cash
                if let institution = institutionForTransaction {
                    institution.cashBalanceSafe -= requiredFunds
                } else {
                    portfolio.addToCash(-requiredFunds)
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
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let assets = holdings.compactMap { holding -> Asset? in
            guard holding.quantity > 0 else { return nil }
            return holding.asset
        }
        // Deduplicate by objectID
        var seen = Set<NSManagedObjectID>()
        var unique: [Asset] = []
        for a in assets {
            if !seen.contains(a.objectID) {
                unique.append(a)
                seen.insert(a.objectID)
            }
        }
        return unique.sorted { ($0.symbol ?? $0.name ?? "") < ($1.symbol ?? $1.name ?? "") }
    }

    private var sellSourceAssets: [Asset] {
        // If no institution is selected, return empty array to disable security selection
        guard let institution = selectedInstitution ??
              ((!tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?
               findExistingInstitution(name: tradingInstitution) : nil) else {
            return []
        }

        // Get assets available at the selected institution
        let institutionAssets = getAssetsAvailableAt(institution: institution)

        // Filter to only include assets we actually hold
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let holdAssets = holdings.compactMap { holding -> Asset? in
            guard holding.quantity > 0 else { return nil }
            return holding.asset
        }

        // Find intersection: assets we hold AND available at this institution
        let availableHoldAssets = institutionAssets.filter { institutionAsset in
            holdAssets.contains { holdAsset in
                holdAsset.objectID == institutionAsset.objectID
            }
        }

        return availableHoldAssets.sorted { ($0.symbol ?? $0.name ?? "") < ($1.symbol ?? $1.name ?? "") }
    }

    private func findExistingInstitution(name: String) -> Institution? {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name.trimmingCharacters(in: .whitespacesAndNewlines))
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
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
        portfolio.totalValue = totalHoldings + portfolio.cashBalanceSafe
        portfolio.updatedAt = Date()
    }
    
    private func convertToPortfolioCurrency(_ amount: Double, from currency: Currency) -> Double {
        currencyService.convertAmount(amount, from: currency, to: portfolioCurrency)
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
            newInstitution.cashBalanceSafe = 0
            return (newInstitution, true)
        }
    }

    private func findOrCreateDepositAsset(for category: DepositCategory, existingAsset: Asset?) -> Asset {
        if let asset = existingAsset, asset.assetType == AssetType.deposit.rawValue {
            asset.symbol = category.assetSymbol
            asset.name = category.assetName
            asset.assetType = AssetType.deposit.rawValue
            asset.lastPriceUpdate = Date()
            asset.setValue(depositInterestRate, forKey: "interestRate")
            return asset
        }

        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, category.assetSymbol)

        if let existingAsset = try? viewContext.fetch(request).first {
            existingAsset.symbol = category.assetSymbol
            existingAsset.name = category.assetName
            existingAsset.assetType = AssetType.deposit.rawValue
            existingAsset.lastPriceUpdate = Date()
            existingAsset.setValue(depositInterestRate, forKey: "interestRate")
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
        newAsset.setValue(depositInterestRate, forKey: "interestRate")
        return newAsset
    }

    private func findOrCreateAsset() -> Asset {
        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "symbol == %@", assetSymbol.uppercased())
        
        if let existingAsset = try? viewContext.fetch(request).first {
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
        
        let holding: Holding
        if let existingHolding = try? viewContext.fetch(request).first {
            holding = existingHolding
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
        
        let transactionCurrency = Currency(rawValue: transaction.currency ?? portfolioCurrency.rawValue) ?? portfolioCurrency
        let quantity = transaction.quantity
        let priceInPortfolioCurrency = currencyService.convertAmount(transaction.price, from: transactionCurrency, to: portfolioCurrency)
        let amountInPortfolioCurrency = currencyService.convertAmount(transaction.amount, from: transactionCurrency, to: portfolioCurrency)

        guard let transactionType = TransactionType(rawValue: transaction.type ?? "") else { return nil }

        var realizedGainForTransaction: Double? = nil

        switch transactionType {
        case .buy:
            let currentCost = holding.quantity * holding.averageCostBasis
            let newTotalCost = currentCost + (quantity * priceInPortfolioCurrency)
            let newTotalQuantity = holding.quantity + quantity
            holding.averageCostBasis = newTotalQuantity > 0 ? newTotalCost / newTotalQuantity : 0
            holding.quantity = newTotalQuantity
            
        case .sell:
            let realizedGain = quantity * (priceInPortfolioCurrency - holding.averageCostBasis)
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

private extension AddTransactionView {
    func insurancePaymentRawAmount() -> Double {
        let normalized = premiumPaymentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "lump sum" {
            return totalPremium
        }
        return singlePremium
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

#Preview {
    AddTransactionView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
