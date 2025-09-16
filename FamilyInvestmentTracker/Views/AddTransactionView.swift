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
    // Dividend-specific: source security
    @State private var selectedDividendAssetID: NSManagedObjectID?
    // Sell-specific: security to sell
    @State private var selectedSellAssetID: NSManagedObjectID?
    
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
        .onChange(of: selectedTransactionType) { _ in
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
        let transaction = Transaction(context: viewContext)
        transaction.id = UUID()
        transaction.type = selectedTransactionType.rawValue
        transaction.transactionDate = transactionDate
        transaction.fees = fees
        transaction.tax = tax
        transaction.currency = selectedCurrency.rawValue

        // Handle institution
        if let selectedInstitution = selectedInstitution {
            transaction.institution = selectedInstitution
            transaction.tradingInstitution = selectedInstitution.name
        } else {
            let institutionName = tradingInstitution.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.tradingInstitution = institutionName

            // Create new institution if needed
            if !institutionName.isEmpty {
                let newInstitution = findOrCreateInstitution(name: institutionName)
                transaction.institution = newInstitution
            }
        }
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.createdAt = Date()
        transaction.portfolio = portfolio
        
        if isAmountOnly {
            transaction.amount = amount
            transaction.quantity = 1
            transaction.price = amount

            // Increase portfolio cash by net amount
            let netCash = amount - fees - tax
            switch selectedTransactionType {
            case .deposit:
                portfolio.addToCash(netCash)
            case .withdrawal:
                portfolio.addToCash(-netCash)
            case .dividend, .interest:
                portfolio.addToCash(netCash)
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
                    portfolio.addToCash(netProceeds)
                }
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
    
    private func findOrCreateInstitution(name: String) -> Institution {
        let request: NSFetchRequest<Institution> = Institution.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)

        if let existingInstitution = try? viewContext.fetch(request).first {
            return existingInstitution
        } else {
            let newInstitution = Institution(context: viewContext)
            newInstitution.id = UUID()
            newInstitution.name = name
            newInstitution.createdAt = Date()
            return newInstitution
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
            newAsset.currentPrice = price
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
        
        switch selectedTransactionType {
        case .buy:
            let newTotalCost = (holding.quantity * holding.averageCostBasis) + (quantity * price)
            let newTotalQuantity = holding.quantity + quantity
            holding.averageCostBasis = newTotalQuantity > 0 ? newTotalCost / newTotalQuantity : 0
            holding.quantity = newTotalQuantity
            
        case .sell:
            let realizedGain = quantity * (price - holding.averageCostBasis)
            holding.realizedGainLoss += realizedGain
            holding.quantity -= quantity
            
        case .dividend, .interest:
            holding.totalDividends += amount
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
