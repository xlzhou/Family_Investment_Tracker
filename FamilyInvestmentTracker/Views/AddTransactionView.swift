import SwiftUI
import CoreData
import Foundation

struct AddTransactionView: View {
    let portfolio: Portfolio
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
    @State private var tax: Double = 0
    @State private var selectedCurrency = Currency.usd
    @State private var hasMaturityDate = false
    @State private var maturityDate = Date()
    // Dividend-specific: source security
    @State private var selectedDividendAssetID: NSManagedObjectID?
    // Sell-specific: security to sell
    @State private var selectedSellAssetID: NSManagedObjectID?
    
    private let currencyService = CurrencyService.shared
    @State private var cashDisciplineError: String?
    
    private var portfolioCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }
    
    private var isAmountOnly: Bool {
        selectedTransactionType == .dividend || selectedTransactionType == .interest || selectedTransactionType == .deposit || selectedTransactionType == .withdrawal
    }
    
    private var requiresTax: Bool {
        selectedTransactionType == .sell || selectedTransactionType == .dividend || selectedTransactionType == .interest
    }

    private var availableInstitutions: [Institution] {
        institutions.compactMap { institution in
            guard let name = institution.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return institution
        }
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
                }
                
                // Asset Information (Buy) or Sell Source selection
                if selectedTransactionType == .buy {
                    Section(header: Text("Asset Information")) {
                        Picker("Asset Type", selection: $selectedAssetType) {
                            ForEach(AssetType.allCases, id: \.self) { type in
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
                    Section(header: Text("Sell Security"), footer: Text("Select the holding you want to sell.")) {
                        Picker("Security", selection: $selectedSellAssetID) {
                            Text("Select...").tag(Optional<NSManagedObjectID>.none)
                            ForEach(sellSourceAssets, id: \.objectID) { asset in
                                Text(asset.symbol ?? asset.name ?? "Unknown")
                                    .tag(Optional(asset.objectID))
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
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
                    Toggle("Set Maturity Date", isOn: $hasMaturityDate.animation())
                    if hasMaturityDate {
                        DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                    }
                    
                    if isAmountOnly {
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
                    }
                    
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
            }
            .navigationTitle("Add Transaction")
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
        .onChange(of: selectedTransactionType) { oldValue, newValue in
            switch selectedTransactionType {
            case .dividend:
                if selectedDividendAssetID == nil { selectedDividendAssetID = dividendSourceAssets.first?.objectID }
                selectedSellAssetID = nil
            case .sell:
                if selectedSellAssetID == nil { selectedSellAssetID = sellSourceAssets.first?.objectID }
                selectedDividendAssetID = nil
            default:
                selectedDividendAssetID = nil
                selectedSellAssetID = nil
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
        case .deposit, .withdrawal:
            // keep same validation as amount-based (optional refinement later)
            return amount > 0 && hasValidInstitution
        }
    }
    
    private func saveTransaction() {
        let trimmedInstitutionName = tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines)
        var createdInstitution: Institution?
        var institutionForTransaction: Institution? = selectedInstitution
        if institutionForTransaction == nil, !trimmedInstitutionName.isEmpty {
            let (institution, wasCreated) = findOrCreateInstitution(name: trimmedInstitutionName)
            institutionForTransaction = institution
            if wasCreated { createdInstitution = institution }
        }

        let cashDisciplineEnabled = portfolio.enforcesCashDisciplineEnabled

        func failWithMessage(_ message: String) {
            if let createdInstitution = createdInstitution {
                viewContext.delete(createdInstitution)
            }
            cashDisciplineError = message
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
                if institution.cashBalanceSafe + 1e-6 < requiredFunds {
                    failWithMessage("Not enough cash in \(institution.name ?? "this institution") to complete this purchase.")
                    return
                }
            case .withdrawal:
                guard let institution = institutionForTransaction else {
                    failWithMessage("Select a trading institution before withdrawing cash.")
                    return
                }
                let netCash = amount - fees - tax
                let requiredCash = max(0, convertToPortfolioCurrency(netCash, from: selectedCurrency))
                if institution.cashBalanceSafe + 1e-6 < requiredCash {
                    failWithMessage("Not enough cash in \(institution.name ?? "this institution") to withdraw this amount.")
                    return
                }
            case .deposit, .sell:
                guard institutionForTransaction != nil else {
                    failWithMessage("Select a trading institution for this transaction.")
                    return
                }
            default:
                break
            }
        }

        let transaction = Transaction(context: viewContext)
        transaction.id = UUID()
        transaction.type = selectedTransactionType.rawValue
        transaction.transactionDate = transactionDate
        transaction.fees = fees
        transaction.tax = tax
        transaction.currency = selectedCurrency.rawValue
        transaction.ensureIdentifiers()

        // Handle institution
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
            transaction.tradingInstitution = trimmedInstitutionName.isEmpty ? nil : trimmedInstitutionName
        }
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.createdAt = Date()
        transaction.portfolio = portfolio
        transaction.maturityDate = hasMaturityDate ? maturityDate : nil
        
        if isAmountOnly {
            transaction.amount = amount
            transaction.quantity = 1
            transaction.price = amount

            // Increase portfolio cash by net amount
            let netCash = amount - fees - tax
            let convertedNetCash = max(0, convertToPortfolioCurrency(netCash, from: selectedCurrency))
            switch selectedTransactionType {
            case .deposit:
                portfolio.addToCash(convertedNetCash)
                if cashDisciplineEnabled, let institution = institutionForTransaction {
                    institution.cashBalanceSafe += convertedNetCash
                }
            case .withdrawal:
                portfolio.addToCash(-convertedNetCash)
                if cashDisciplineEnabled, let institution = institutionForTransaction {
                    institution.cashBalanceSafe -= convertedNetCash
                }
            case .dividend, .interest:
                portfolio.addToCash(convertedNetCash)
            default:
                break
            }

            // Record source security for dividends if provided
            if selectedTransactionType == .dividend, let id = selectedDividendAssetID,
               let srcAsset = try? viewContext.existingObject(with: id) as? Asset {
                transaction.asset = srcAsset
            }
        } else {
            transaction.quantity = quantity
            transaction.price = price
            transaction.amount = quantity * price
            
            // Determine asset based on type
            let asset: Asset
            if selectedTransactionType == .sell, let id = selectedSellAssetID,
               let selected = try? viewContext.existingObject(with: id) as? Asset {
                asset = selected
            } else {
                // Buy or fallback: create/find from entered fields
                asset = findOrCreateAsset()
            }
            transaction.asset = asset
            
            // Update or create holding
            updateHolding(for: asset, transaction: transaction)

            // Cash movement for sell: deposit net proceeds into cash account
            if selectedTransactionType == .sell {
                let netProceeds = (quantity * price) - fees - tax
                if netProceeds != 0 {
                    let convertedProceeds = convertToPortfolioCurrency(netProceeds, from: selectedCurrency)
                    portfolio.addToCash(convertedProceeds)
                    if cashDisciplineEnabled, let institution = institutionForTransaction {
                        institution.cashBalanceSafe += convertedProceeds
                    }
                }
            } else if selectedTransactionType == .buy, cashDisciplineEnabled, let institution = institutionForTransaction {
                let requiredFundsTransactionCurrency = (quantity * price) + fees + tax
                let requiredFunds = max(0, convertToPortfolioCurrency(requiredFundsTransactionCurrency, from: selectedCurrency))
                institution.cashBalanceSafe -= requiredFunds
                portfolio.addToCash(-requiredFunds)
            }
        }
        
        // Recompute portfolio totals based on holdings' current prices
        recomputePortfolioTotals()
        
        do {
            try viewContext.save()
            print("✅ Transaction saved successfully: \(transaction.type ?? "Unknown") - \(transaction.amount)")
            dismiss()
        } catch {
            print("❌ Error saving transaction: \(error)")
            print("Transaction details: type=\(selectedTransactionType.rawValue), amount=\(transaction.amount), institution=\(tradingInstitution)")
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

    private var sellSourceAssets: [Asset] { dividendSourceAssets }

    private func recomputePortfolioTotals() {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let totalHoldings = holdings.reduce(0.0) { partial, holding in
            guard let asset = holding.asset else { return partial }
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
    
    private func updateHolding(for asset: Asset, transaction: Transaction) {
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

        guard let transactionType = TransactionType(rawValue: transaction.type ?? "") else { return }

        switch transactionType {
        case .buy:
            let currentCost = holding.quantity * holding.averageCostBasis
            let newTotalCost = currentCost + (quantity * priceInPortfolioCurrency)
            let newTotalQuantity = holding.quantity + quantity
            holding.averageCostBasis = newTotalQuantity > 0 ? newTotalCost / newTotalQuantity : 0
            holding.quantity = newTotalQuantity
            asset.currentPrice = priceInPortfolioCurrency
            asset.lastPriceUpdate = Date()
            
        case .sell:
            let realizedGain = quantity * (priceInPortfolioCurrency - holding.averageCostBasis)
            holding.realizedGainLoss += realizedGain
            holding.quantity -= quantity
            asset.currentPrice = priceInPortfolioCurrency
            asset.lastPriceUpdate = Date()
            if holding.quantity < 0 {
                holding.quantity = 0
            }
            if holding.quantity == 0 {
                holding.averageCostBasis = 0
            }
            
        case .dividend, .interest:
            holding.totalDividends += amountInPortfolioCurrency
        case .deposit, .withdrawal:
            // No holding changes for cash movements
            break
        }
        
        holding.updatedAt = Date()
        print("📈 Updated holding for \(asset.symbol ?? "Unknown"): qty=\(holding.quantity), cost=\(holding.averageCostBasis), dividends=\(holding.totalDividends)")
    }
}

#Preview {
    AddTransactionView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
