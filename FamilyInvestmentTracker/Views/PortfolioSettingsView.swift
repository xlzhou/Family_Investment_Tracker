import SwiftUI
import CoreData

struct PortfolioSettingsView: View {
    let portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    private let currencyService = CurrencyService.shared
    
    @State private var portfolioName: String
    @State private var selectedMainCurrency: Currency
    @State private var newInstitutionName: String = ""
    @State private var editingInstitution: Institution?
    @State private var editingInstitutionName: String = ""
    @State private var activeAlert: ActiveAlert?
    @State private var institutionPendingDeletion: Institution?
    @State private var enforceCashDiscipline: Bool
    @StateObject private var ownershipService = PortfolioOwnershipService.shared
    @State private var ownerName: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Institution.name, ascending: true)],
        animation: .default
    ) private var institutions: FetchedResults<Institution>

    private enum ActiveAlert: String, Identifiable {
        case deleteInstitution
        case resetPortfolio
        case deletePortfolio

        var id: String { rawValue }
    }

    init(portfolio: Portfolio) {
        self.portfolio = portfolio
        _portfolioName = State(initialValue: portfolio.name ?? "")
        _selectedMainCurrency = State(initialValue: Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd)
        _enforceCashDiscipline = State(initialValue: portfolio.enforcesCashDisciplineEnabled)

    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Portfolio Information")) {
                    TextField("Portfolio Name", text: $portfolioName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Toggle("Enforce Cash Discipline", isOn: $enforceCashDiscipline)
                        .tint(.blue)
                    Text("When enabled, security purchases must have sufficient cash in the selected institution.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }


                Section(header: Text("Currency Settings"),
                       footer: Text("All asset values will be converted to your main currency for total portfolio calculations.")) {
                    Picker("Main Currency", selection: $selectedMainCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    HStack {
                        Text("Current Exchange Rates")
                        Spacer()
                        Button("View Rates") {
                            // Future: Show exchange rates view
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                
                Section(
                    header: Text("Trading Institutions"),
                    footer: Text("Institution names are shared across all portfolios.")
                ) {
                    ForEach(institutions, id: \.objectID) { institution in
                        if editingInstitution?.objectID == institution.objectID {
                            HStack {
                                TextField("Institution name", text: $editingInstitutionName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Save") {
                                    saveInstitutionEdit()
                                }
                                .disabled(editingInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Cancel") {
                                    cancelInstitutionEdit()
                                }
                                .foregroundColor(.red)
                            }
                        } else {
                            HStack {
                                Text(institution.name ?? "Unknown")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                startEditingInstitution(institution)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    institutionPendingDeletion = institution
                                    activeAlert = .deleteInstitution
                                }
                                .tint(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("Add new institution", text: $newInstitutionName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Add") {
                            addInstitution()
                        }
                        .disabled(newInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Danger Zone"), footer: Text("Resetting clears this portfolio's holdings, transactions, cash balance, and analytics calculations. Institutions stay available for other portfolios.")) {
                    Button(role: .destructive) {
                        activeAlert = .resetPortfolio
                    } label: {
                        Text("Reset Portfolio Data")
                    }
                    .disabled(isResetDisabled)

                    if ownershipService.canDeletePortfolio(portfolio) {
                        Button(role: .destructive) {
                            activeAlert = .deletePortfolio
                        } label: {
                            Text("Delete Portfolio")
                        }
                    }
                }

                Section(header: Text("Statistics")) {
                    HStack {
                        Text("Portfolio Owner")
                        Spacer()
                        if let ownerName = ownerName {
                            Text(ownerName)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        } else {
                            Text("Loading...")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Total Holdings")
                        Spacer()
                        Text("\(portfolio.holdings?.count ?? 0)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Total Transactions")
                        Spacer()
                        Text("\(portfolio.transactions?.count ?? 0)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Created")
                        Spacer()
                        if let createdAt = portfolio.createdAt {
                            Text(createdAt, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Portfolio Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveSettings()
                    }
                    .disabled(portfolioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .deleteInstitution:
                let name = institutionPendingDeletion?.name ?? "this institution"
                return Alert(
                    title: Text("Delete Institution"),
                    message: Text("Are you sure you want to delete \"\(name)\"? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let institution = institutionPendingDeletion {
                            deleteInstitution(institution)
                        }
                        institutionPendingDeletion = nil
                    },
                    secondaryButton: .cancel {
                        institutionPendingDeletion = nil
                    }
                )
            case .resetPortfolio:
                return Alert(
                    title: Text("Reset Portfolio Data"),
                    message: Text("This removes all holdings, transactions, cash, and analytics data for this portfolio. Institutions remain untouched. This cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        resetPortfolioData()
                    },
                    secondaryButton: .cancel()
                )
            case .deletePortfolio:
                return Alert(
                    title: Text("Delete Portfolio"),
                    message: Text("This will permanently delete \"\(portfolio.name ?? "this portfolio")\" and all its data. This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        deletePortfolio()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear {
            // Get the portfolio owner name for display in Statistics
            ownershipService.getOwnerName(for: portfolio) { name in
                ownerName = name
            }
        }
    }

    private func saveSettings() {
        let previousCurrency = Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
        let newCurrency = selectedMainCurrency

        if previousCurrency != newCurrency {
            applyCurrencyChange(from: previousCurrency, to: newCurrency)
        }

        portfolio.name = portfolioName.trimmingCharacters(in: .whitespacesAndNewlines)
        portfolio.mainCurrency = newCurrency.rawValue
        portfolio.updatedAt = Date()
        portfolio.enforcesCashDisciplineEnabled = enforceCashDiscipline

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving portfolio settings: \(error)")
        }
    }

    private var isResetDisabled: Bool {
        let hasHoldings = (portfolio.holdings?.count ?? 0) > 0
        let hasTransactions = (portfolio.transactions?.count ?? 0) > 0
        let hasBalance = abs(portfolio.resolvedCashBalance()) > 0.01
        let hasTotals = portfolio.totalValue != 0
        return !(hasHoldings || hasTransactions || hasBalance || hasTotals)
    }

    private func addInstitution() {
        let trimmedName = newInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Check if institution already exists
        if institutions.contains(where: { $0.name?.lowercased() == trimmedName.lowercased() }) {
            return // Don't add duplicate
        }

        let institution = Institution(context: viewContext)
        institution.id = UUID()
        institution.name = trimmedName
        institution.createdAt = Date()

        newInstitutionName = ""

        do {
            try viewContext.save()
        } catch {
            print("Error adding institution: \(error)")
        }
    }

    private func startEditingInstitution(_ institution: Institution) {
        editingInstitution = institution
        editingInstitutionName = institution.name ?? ""
    }

    private func saveInstitutionEdit() {
        guard let institution = editingInstitution else { return }
        let trimmedName = editingInstitutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Check if another institution already has this name
        if institutions.contains(where: { $0.objectID != institution.objectID && $0.name?.lowercased() == trimmedName.lowercased() }) {
            return // Don't allow duplicate names
        }

        institution.name = trimmedName
        editingInstitution = nil
        editingInstitutionName = ""

        do {
            try viewContext.save()
        } catch {
            print("Error updating institution: \(error)")
        }
    }

    private func cancelInstitutionEdit() {
        editingInstitution = nil
        editingInstitutionName = ""
    }

    private func deleteInstitution(_ institution: Institution) {
        viewContext.delete(institution)

        do {
            try viewContext.save()
        } catch {
            print("Error deleting institution: \(error)")
        }
    }

    private func resetPortfolioData() {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []

        transactions.forEach(viewContext.delete)
        holdings.forEach(viewContext.delete)

        portfolio.cashBalance = 0
        portfolio.totalValue = 0
        portfolio.updatedAt = Date()

        if let currencyBalances = portfolio.currencyCashBalances?.allObjects as? [PortfolioInstitutionCurrencyCash] {
            currencyBalances.forEach(viewContext.delete)
        }

        do {
            try viewContext.save()
        } catch {
            print("Error resetting portfolio data: \(error)")
        }
    }

    private func deletePortfolio() {
        // Only allow owner to delete
        guard ownershipService.canDeletePortfolio(portfolio) else {
            print("Only the portfolio owner can delete this portfolio")
            return
        }

        // Delete all related data
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []

        transactions.forEach(viewContext.delete)
        holdings.forEach(viewContext.delete)

        // Delete the portfolio itself
        viewContext.delete(portfolio)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error deleting portfolio: \(error)")
        }
    }
}

private extension PortfolioSettingsView {
    func applyCurrencyChange(from oldCurrency: Currency, to newCurrency: Currency) {
        print("🔄 Currency change: \(oldCurrency.rawValue) → \(newCurrency.rawValue)")

        let convert: (Double) -> Double = { amount in
            currencyService.convertAmount(amount, from: oldCurrency, to: newCurrency)
        }

        portfolio.cashBalance = convert(portfolio.cashBalance)
        portfolio.totalValue = convert(portfolio.totalValue)

        if let holdings = portfolio.holdings?.allObjects as? [Holding] {
            for holding in holdings {
                holding.averageCostBasis = convert(holding.averageCostBasis)
                holding.realizedGainLoss = convert(holding.realizedGainLoss)
                holding.totalDividends = convert(holding.totalDividends)

                if let cashValue = holding.value(forKey: "cashValue") as? Double {
                    holding.setValue(convert(cashValue), forKey: "cashValue")
                }

                if let asset = holding.asset {
                    convertAssetPriceIfSafe(asset, using: convert)
                    if let insurance = asset.value(forKey: "insurance") as? NSManagedObject {
                        convertInsuranceValues(insurance, using: convert)
                    }
                }
            }
        }

        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        for transaction in transactions {
            let realized = transaction.realizedGainAmount
            if realized != 0 {
                transaction.realizedGainAmount = convert(realized)
            }

            if let deducted = transaction.value(forKey: "paymentDeductedAmount") as? Double {
                transaction.setValue(convert(deducted), forKey: "paymentDeductedAmount")
            }
        }

        portfolio.cashBalance = convert(portfolio.cashBalance)
    }

    func convertAssetPriceIfSafe(_ asset: Asset, using convert: (Double) -> Double) {
        guard let holdings = asset.holdings?.allObjects as? [Holding] else { return }
        let otherPortfolios = holdings.compactMap { $0.portfolio }.filter { $0 != portfolio }
        if otherPortfolios.isEmpty {
            asset.currentPrice = convert(asset.currentPrice)
        }
    }

    func convertInsuranceValues(_ insurance: NSManagedObject, using convert: (Double) -> Double) {
        let monetaryKeys = [
            "basicInsuredAmount",
            "additionalPaymentAmount",
            "deathBenefit",
            "singlePremium",
            "totalPremium",
            "estimatedMaturityBenefit"
        ]

        for key in monetaryKeys {
            if let value = insurance.value(forKey: key) as? Double {
                insurance.setValue(convert(value), forKey: key)
            }
        }
    }
}

#Preview {
    PortfolioSettingsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
