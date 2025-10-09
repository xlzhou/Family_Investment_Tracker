import SwiftUI
import CoreData

struct AddFixedDepositView: View {
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var depositName = ""
    @State private var symbol = ""
    @State private var amount = ""
    @State private var termMonths: Int = 12
    @State private var interestRate = ""
    @State private var allowEarlyWithdrawal = false
    @State private var selectedInstitution: Institution?
    @State private var selectedCurrency = Currency.usd
    @State private var valueDate = Calendar.current.startOfDay(for: Date())
    @State private var errorMessage = ""
    @State private var showingInsufficientCashAlert = false
    @State private var availableCashFormatted = ""
    @State private var requiredCashFormatted = ""

    // Institution management
    @State private var showingInstitutionPicker = false
    @State private var newInstitutionName = ""
    @State private var existingInstitutions: [Institution] = []

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private var termYears: Double {
        Double(termMonths) / 12.0
    }

    private var maturityDate: Date {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: valueDate)
        let calculated = calendar.date(byAdding: .month, value: termMonths, to: normalizedStart) ?? normalizedStart
        return calendar.startOfDay(for: calculated)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Institution")) {
                    Button(action: {
                        showingInstitutionPicker = true
                    }) {
                        HStack {
                            Text("Institution")
                            Spacer()
                            Text(selectedInstitution?.name ?? "Select Institution")
                                .foregroundColor(selectedInstitution == nil ? .secondary : .primary)
                        }
                    }
                }
                Section(header: Text("Fixed Deposit Details")) {

                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    DatePicker(
                        "Value Date",
                        selection: Binding(
                            get: { valueDate },
                            set: { newValue in
                                valueDate = Calendar.current.startOfDay(for: newValue)
                            }
                        ),
                        displayedComponents: .date
                    )

                    Stepper(value: $termMonths, in: 1...240, step: 1) {
                        HStack {
                            Text("Term")
                            Spacer()
                            if termMonths >= 12 {
                                Text("\(Int(termYears)) year\(Int(termYears) > 1 ? "s" : "") (\(termMonths) months)")
                            } else {
                                Text("\(termMonths) month\(termMonths > 1 ? "s" : "")")
                            }
                        }
                    }

                    HStack {
                        Text("Interest Rate (%)")
                        Spacer()
                        TextField("0.00", text: $interestRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Maturity Date")
                        Spacer()
                        Text(maturityDate, style: .date)
                            .foregroundColor(.secondary)
                    }

                    TextField("Deposit Name", text: $depositName)
                    TextField("Symbol (auto-generated)", text: $symbol)

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                //Section(header: Text("Term & Interest")) {
               //}


                Section(header: Text("Options")) {
                    Toggle("Allow Early Withdrawal", isOn: $allowEarlyWithdrawal)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Fixed Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createFixedDeposit()
                    }
                    .disabled(!isValidInput)
                }
            }
            .sheet(isPresented: $showingInstitutionPicker) {
                InstitutionPickerView(
                    selectedInstitution: $selectedInstitution,
                    portfolio: portfolio
                )
            }
            .onAppear {
                loadExistingInstitutions()
                setupDefaults()
            }
            .onChange(of: selectedInstitution) { _, newInstitution in
                updateSymbolSuggestion()
            }
            .onChange(of: termMonths) { _, newTerm in
                updateSymbolSuggestion()
            }
            .onChange(of: selectedCurrency) { _, newCurrency in
                updateSymbolSuggestion()
            }
            .onChange(of: interestRate) { _, newRate in
                updateSymbolSuggestion()
            }
            .alert("Insufficient Cash", isPresented: $showingInsufficientCashAlert) {
                Button("OK") { }
            } message: {
                let institutionName = selectedInstitution?.name ?? "Selected institution"
                Text("\(institutionName) available: \(availableCashFormatted)\nRequired: \(requiredCashFormatted)\n\nIf you do not want cash to be deducted when creating a fixed deposit, go to portfolio settings and turn off 'Enforce Cash Discipline'.")
            }
        }
    }

    private var isValidInput: Bool {
        !depositName.isEmpty &&
        !amount.isEmpty &&
        Double(amount) != nil &&
        Double(amount)! > 0 &&
        selectedInstitution != nil &&
        (!interestRate.isEmpty ? Double(interestRate) != nil : true)
    }

    private func setupDefaults() {
        selectedCurrency = mainCurrency

        // Auto-generate name with term, currency, and institution
        if depositName.isEmpty {
            updateDepositName()
        }
    }
    private func formatInterestRate(_ rateString: String) -> String {
        guard let rate = Double(rateString), rate > 0 else { return "" }

        // Format with appropriate decimal places and % symbol
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", rate)  // "3%"
        } else {
            return String(format: "%.2f%%", rate)  // "3.25%"
        }
    }
    private func updateDepositName() {
        let termString: String
        if termMonths >= 12 {
            let years = termMonths / 12
            termString = "\(years)-Year"
        } else {
            termString = "\(termMonths)-Month"
        }

        let currencyString = selectedCurrency.rawValue
        let currencySymbol = selectedCurrency.symbol
        let interestRateFormatted = formatInterestRate(interestRate)

        if let institution = selectedInstitution {
            depositName = "\(termString) \(currencyString) \(currencySymbol) \(interestRateFormatted) FD - \(institution.name ?? "Bank")"
        } else {
            depositName = "\(termString) \(currencyString) \(currencySymbol) \(interestRateFormatted) FD"
        }
    }

    private func updateSymbolSuggestion() {
        // Auto-generate symbol using standardized format: "short form term"-"currency"-"FD"-"short form institution"
        if let institution = selectedInstitution {
            let termShortForm = getTermShortForm(termMonths)
            let institutionShortForm = getInstitutionShortForm(institution)
            let interestRateFormatted = formatInterestRate(interestRate)
            symbol = "\(termShortForm)-\(selectedCurrency.rawValue)\(interestRateFormatted)-FD-\(institutionShortForm)"
        }

        // Update name with term, currency, and institution
        updateDepositName()
    }

    /// Get short form for term (e.g., "1Y" for 12 months, "3M" for 3 months)
    private func getTermShortForm(_ termMonths: Int) -> String {
        if termMonths >= 12 {
            let years = termMonths / 12
            let remainingMonths = termMonths % 12
            if remainingMonths > 0 {
                return "\(years)Y\(remainingMonths)M"
            } else {
                return "\(years)Y"
            }
        } else {
            return "\(termMonths)M"
        }
    }

    /// Get short form for institution name (first 3 characters, uppercase)
    private func getInstitutionShortForm(_ institution: Institution) -> String {
        guard let name = institution.name else { return "BNK" }

        // Remove spaces and special characters, take first 3 characters
        let cleanedName = name.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
        let shortForm = String(cleanedName.prefix(3)).uppercased()

        return shortForm.isEmpty ? "BNK" : shortForm
    }

    private func loadExistingInstitutions() {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Institution.name, ascending: true)]

        do {
            existingInstitutions = try viewContext.fetch(request)
        } catch {
            print("Error loading institutions: \(error)")
        }
    }

    private func createFixedDeposit() {
        guard let amountValue = Double(amount),
              let institution = selectedInstitution else {
            errorMessage = "Invalid input values"
            return
        }

        let interestRateValue = Double(interestRate) ?? 0.0

        do {
            // Check cash discipline enforcement
            if portfolio.enforcesCashDisciplineEnabled {
                // First verify the selected institution has enough cash in this currency
                let institutionBalance = portfolio.getCurrencyBalance(
                    for: institution,
                    currency: selectedCurrency.rawValue
                )

                if institutionBalance + 1e-6 < amountValue {
                    availableCashFormatted = CurrencyService.shared.formatAmount(institutionBalance, in: selectedCurrency)
                    requiredCashFormatted = CurrencyService.shared.formatAmount(amountValue, in: selectedCurrency)
                    showingInsufficientCashAlert = true
                    return
                }

                // Extra safety: ensure portfolio-level available cash in this currency is also sufficient
                let availableCashInCurrency = CashBalanceService.shared.getAvailableCashBalance(for: portfolio, currency: selectedCurrency)
                if availableCashInCurrency + 1e-6 < amountValue {
                    availableCashFormatted = CurrencyService.shared.formatAmount(availableCashInCurrency, in: selectedCurrency)
                    requiredCashFormatted = CurrencyService.shared.formatAmount(amountValue, in: selectedCurrency)
                    showingInsufficientCashAlert = true
                    return
                }
            }

            let fixedDeposit = FixedDepositService.shared.createFixedDeposit(
                name: depositName,
                symbol: symbol.isEmpty ? nil : symbol,
                institution: institution,
                portfolio: portfolio,
                amount: amountValue,
                currency: selectedCurrency,
                termMonths: termMonths,
                interestRate: interestRateValue,
                allowEarlyWithdrawal: allowEarlyWithdrawal,
                valueDate: valueDate,
                context: viewContext
            )

            // Create the initial deposit transaction for the fixed deposit
            let transaction = Transaction(context: viewContext)
           transaction.id = UUID()
            transaction.createdAt = valueDate
            transaction.transactionDate = valueDate
            transaction.type = TransactionType.deposit.rawValue
            transaction.amount = amountValue
            transaction.quantity = 1
            transaction.price = amountValue
            transaction.fees = 0
            transaction.tax = 0
            transaction.currency = selectedCurrency.rawValue
            transaction.portfolio = portfolio
            transaction.institution = institution
            transaction.asset = fixedDeposit
            transaction.tradingInstitution = institution.name
            transaction.autoFetchPrice = false
            transaction.notes = "Initial deposit for \(depositName)"
            transaction.ensureIdentifiers()

            // If cash discipline is enabled, create negative demand deposit transaction to reduce available cash
            if portfolio.enforcesCashDisciplineEnabled {
                let demandAsset = findOrCreateDemandDepositAsset()
                let negativeTransaction = Transaction(context: viewContext)
                negativeTransaction.id = UUID()
                negativeTransaction.createdAt = valueDate
                negativeTransaction.transactionDate = valueDate
                negativeTransaction.type = TransactionType.depositWithdrawal.rawValue
                negativeTransaction.amount = amountValue
                negativeTransaction.quantity = 1
                negativeTransaction.price = amountValue
                negativeTransaction.fees = 0
                negativeTransaction.tax = 0
                negativeTransaction.currency = selectedCurrency.rawValue
                negativeTransaction.portfolio = portfolio
                negativeTransaction.institution = institution
                negativeTransaction.asset = demandAsset
                negativeTransaction.tradingInstitution = institution.name
                negativeTransaction.autoFetchPrice = false
                negativeTransaction.notes = "Transfer to fixed deposit: \(depositName)"
                negativeTransaction.ensureIdentifiers()
                if let transactionID = transaction.id {
                    negativeTransaction.setValue(transactionID, forKey: "linkedTransactionID")
                }

                maintainInstitutionAssetRelationship(institution: institution,
                                                     asset: demandAsset,
                                                     transactionDate: valueDate)

                // Reduce available cash balance
                CashBalanceService.shared.addToAvailableCashBalance(
                    for: portfolio,
                    institution: institution,
                    currency: selectedCurrency,
                    delta: -amountValue
                )
            }

            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to create fixed deposit: \(error.localizedDescription) "
        }
    }

    private func findOrCreateDemandDepositAsset() -> Asset {
        let symbol = DepositCategory.demand.assetSymbol
        let name = DepositCategory.demand.assetName

        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, symbol)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            if (existing.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.symbol = symbol
            }
            if (existing.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = name
            }
            existing.assetType = AssetType.deposit.rawValue
            existing.depositSubtypeEnum = .demand
            existing.lastPriceUpdate = Date()
            return existing
        }

        let asset = Asset(context: viewContext)
        asset.id = UUID()
        asset.symbol = symbol
        asset.name = name
        asset.assetType = AssetType.deposit.rawValue
        asset.createdAt = Date()
        asset.lastPriceUpdate = Date()
        asset.currentPrice = 0
        asset.depositSubtypeEnum = .demand
        asset.ensureIdentifier()
        return asset
    }

    private func maintainInstitutionAssetRelationship(institution: Institution,
                                                      asset: Asset,
                                                      transactionDate: Date) {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@ AND asset == %@", institution, asset)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            existing.lastTransactionDate = transactionDate
        } else {
            let availability = InstitutionAssetAvailability(context: viewContext)
            availability.id = UUID()
            availability.createdAt = Date()
            availability.lastTransactionDate = transactionDate
            availability.institution = institution
            availability.asset = asset
        }
    }
}

struct InstitutionPickerView: View {
    @Binding var selectedInstitution: Institution?
    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var institutions: [Institution] = []
    @State private var newInstitutionName = ""
    @State private var showingAddInstitution = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Select Institution")) {
                    ForEach(institutions, id: \.objectID) { institution in
                        Button(action: {
                            selectedInstitution = institution
                            dismiss()
                        }) {
                            HStack {
                                Text(institution.name ?? "Unknown Institution")
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedInstitution == institution {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(action: {
                        showingAddInstitution = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add New Institution")
                        }
                    }
                }
            }
            .navigationTitle("Choose Institution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Add Institution", isPresented: $showingAddInstitution) {
                TextField("Institution Name", text: $newInstitutionName)
                Button("Add") {
                    addNewInstitution()
                }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                loadInstitutions()
            }
        }
    }

    private func loadInstitutions() {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Institution.name, ascending: true)]

        do {
            institutions = try viewContext.fetch(request)
        } catch {
            print("Error loading institutions: \(error)")
        }
    }

    private func addNewInstitution() {
        guard !newInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let institution = Institution(context: viewContext)
        institution.id = UUID()
        institution.name = newInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        institution.createdAt = Date()

        do {
            try viewContext.save()
            selectedInstitution = institution
            loadInstitutions()
            newInstitutionName = ""
        } catch {
            print("Error adding institution: \(error)")
        }
    }

    private func findOrCreateDemandDepositAsset() -> Asset {
        let symbol = "Demand Deposit"
        let name = "Demand Deposit"

        let request: NSFetchRequest<Asset> = Asset.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND symbol ==[c] %@", AssetType.deposit.rawValue, symbol)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            if (existing.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.symbol = symbol
            }
            if (existing.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = name
            }
            existing.assetType = AssetType.deposit.rawValue
            existing.depositSubtypeEnum = .demand
            existing.lastPriceUpdate = Date()
            return existing
        }

        let asset = Asset(context: viewContext)
        asset.id = UUID()
        asset.symbol = symbol
        asset.name = name
        asset.assetType = AssetType.deposit.rawValue
        asset.createdAt = Date()
        asset.lastPriceUpdate = Date()
        asset.currentPrice = 0
        asset.depositSubtypeEnum = .demand
        asset.ensureIdentifier()
        return asset
    }

    private func maintainInstitutionAssetRelationship(institution: Institution,
                                                      asset: Asset,
                                                      transactionDate: Date) {
        let request: NSFetchRequest<InstitutionAssetAvailability> = NSFetchRequest(entityName: "InstitutionAssetAvailability")
        request.predicate = NSPredicate(format: "institution == %@ AND asset == %@", institution, asset)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            existing.lastTransactionDate = transactionDate
        } else {
            let availability = InstitutionAssetAvailability(context: viewContext)
            availability.id = UUID()
            availability.createdAt = Date()
            availability.lastTransactionDate = transactionDate
            availability.institution = institution
            availability.asset = asset
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "Test Portfolio"
    portfolio.mainCurrency = "USD"

    return AddFixedDepositView(portfolio: portfolio)
        .environment(\.managedObjectContext, context)
}
