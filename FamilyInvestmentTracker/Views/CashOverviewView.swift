import SwiftUI
import CoreData

struct CashOverviewView: View {
    enum Tab: Hashable {
        case demandCash
        case fixedDeposits

        func title(localizationManager: LocalizationManager) -> String {
            switch self {
            case .demandCash: return localizationManager.localizedString(for: "cashOverview.tabs.demandCash")
            case .fixedDeposits: return localizationManager.localizedString(for: "cashOverview.tabs.fixedDeposits")
            }
        }
    }

    @ObservedObject var portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyService = CurrencyService.shared
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var selectedTab: Tab

    // Demand cash state
    @State private var editContext: CashBalanceEditContext?

    // Fixed deposit state
    @State private var activeDeposits: [Asset] = []
    @State private var maturedDeposits: [Asset] = []
    @State private var showingAddFixedDeposit = false
    @State private var selectedDeposit: Asset?
    @State private var showingWithdrawalView = false
    @State private var showingMaturityAlert = false
    @State private var maturityAlertDepositNames: [String] = []
    @State private var hasShownMaturityAlert = false

    init(portfolio: Portfolio, initialTab: Tab = .demandCash) {
        self.portfolio = portfolio
        _selectedTab = State(initialValue: initialTab)
    }

    private var mainCurrency: Currency {
        Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd
    }

    private struct CashBalanceEditContext: Identifiable {
        let institution: Institution
        let currencyBalance: PortfolioInstitutionCurrencyCash
        let currency: Currency

        var id: NSManagedObjectID { currencyBalance.objectID }
    }

    private var institutionsWithCash: [(Institution, [PortfolioInstitutionCurrencyCash], Double)] {
        let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
        let institutionSet = Set(transactions.compactMap { $0.institution })

        return institutionSet.compactMap { institution in
            let currencyBalances = institution.getAllCurrencyBalances(for: portfolio)

            let nonZeroBalances = currencyBalances.filter {
                let amount = ($0.value(forKey: "amount") as? Double) ?? 0.0
                return amount != 0.0
            }

            guard !nonZeroBalances.isEmpty else {
                return nil
            }

            let totalInMainCurrency = institution.getCashBalance(for: portfolio)

            return (institution, nonZeroBalances, totalInMainCurrency)
        }
        .sorted { ($0.0.name ?? "") < ($1.0.name ?? "") }
    }

    private var totalDemandCash: Double {
        institutionsWithCash.reduce(0) { $0 + $1.2 }
    }

    private var totalFixedDepositValue: Double {
        (activeDeposits + maturedDeposits).reduce(0) { partial, asset in
            partial + valueInMainCurrency(for: asset)
        }
    }

    private var grandTotalCash: Double {
        totalDemandCash + totalFixedDepositValue
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    summaryCard
                    tabPicker
                }

                switch selectedTab {
                case .demandCash:
                    demandCashSection
                case .fixedDeposits:
                    fixedDepositSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(localizationManager.localizedString(for: "cashOverview.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "cashOverview.navigation.done")) { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == .fixedDeposits {
                        Button {
                            showingAddFixedDeposit = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(item: $editContext) { context in
                CashBalanceEditSheet(
                    institution: context.institution,
                    currencyBalance: context.currencyBalance,
                    currency: context.currency
                ) {
                    refreshPortfolioAggregates()
                }
                .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingAddFixedDeposit) {
                AddFixedDepositView(portfolio: portfolio)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingWithdrawalView) {
                if let deposit = selectedDeposit {
                    FixedDepositWithdrawalView(deposit: deposit, portfolio: portfolio)
                        .environment(\.managedObjectContext, viewContext)
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
            .alert(localizationManager.localizedString(for: "cashOverview.fixedDeposits.maturityAlert.title"), isPresented: $showingMaturityAlert, presenting: maturityAlertDepositNames) { names in
                Button(localizationManager.localizedString(for: "cashOverview.fixedDeposits.maturityAlert.review")) {
                    selectedTab = .fixedDeposits
                    showingMaturityAlert = false
                }
                Button(localizationManager.localizedString(for: "cashOverview.fixedDeposits.maturityAlert.dismiss"), role: .cancel) {
                    showingMaturityAlert = false
                }
            } message: { names in
                Text(names.joined(separator: "\n"))
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.localizedString(for: "cashOverview.summary.overview"))
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                summaryRow(title: localizationManager.localizedString(for: "cashOverview.tabs.demandCash"),
                           value: currencyService.formatAmount(totalDemandCash, in: mainCurrency),
                           highlighted: selectedTab == .demandCash)

                summaryRow(title: localizationManager.localizedString(for: "cashOverview.tabs.fixedDeposits"),
                           value: currencyService.formatAmount(totalFixedDepositValue, in: mainCurrency),
                           highlighted: selectedTab == .fixedDeposits)

                Divider()

                summaryRow(title: localizationManager.localizedString(for: "cashOverview.summary.totalCash"),
                           value: currencyService.formatAmount(grandTotalCash, in: mainCurrency),
                           highlighted: false,
                           weight: .semibold)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private func summaryRow(title: String,
                            value: String,
                            highlighted: Bool,
                            weight: Font.Weight = .regular) -> some View {
        HStack {
            Text(title)
                .fontWeight(highlighted ? .semibold : .regular)
                .foregroundColor(highlighted ? .primary : .secondary)

            Spacer()

            Text(value)
                .fontWeight(weight)
                .foregroundColor(highlighted ? .primary : .secondary)
        }
        .font(.subheadline)
    }

    private var tabPicker: some View {
        Picker(localizationManager.localizedString(for: "cashOverview.tabs.pickerLabel"), selection: $selectedTab) {
            Text(Tab.demandCash.title(localizationManager: localizationManager)).tag(Tab.demandCash)
            Text(Tab.fixedDeposits.title(localizationManager: localizationManager)).tag(Tab.fixedDeposits)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var demandCashSection: some View {
        if institutionsWithCash.isEmpty {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "banknote")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(localizationManager.localizedString(for: "cashOverview.demandCash.noCashTitle"))
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(localizationManager.localizedString(for: "cashOverview.demandCash.noCashMessage"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            Section(header: Text(localizationManager.localizedString(for: "cashOverview.demandCash.sectionHeader"))) {
                ForEach(institutionsWithCash, id: \.0.objectID) { institutionData in
                    let (institution, currencyBalances, totalInMainCurrency) = institutionData

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(institution.name ?? localizationManager.localizedString(for: "cashOverview.demandCash.unknownInstitution"))
                                    .font(.headline)
                                Text("\(currencyBalances.count) " + (currencyBalances.count == 1 ? localizationManager.localizedString(for: "cashOverview.demandCash.currency") : localizationManager.localizedString(for: "cashOverview.demandCash.currencies")))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(currencyService.formatAmountWithFullCurrency(totalInMainCurrency, in: mainCurrency))
                                    .font(.headline)
                                    .foregroundColor(totalInMainCurrency >= 0 ? .primary : .red)
                                Text(localizationManager.localizedString(for: "cashOverview.demandCash.total"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        ForEach(currencyBalances.sorted(by: {
                            let currency1 = ($0.value(forKey: "currency") as? String) ?? ""
                            let currency2 = ($1.value(forKey: "currency") as? String) ?? ""
                            return currency1 < currency2
                        }), id: \.objectID) { currencyBalance in
                            let currencyCode = (currencyBalance.value(forKey: "currency") as? String) ?? "USD"
                            let currency = Currency(rawValue: currencyCode) ?? .usd
                            let amount = (currencyBalance.value(forKey: "amount") as? Double) ?? 0.0

                            HStack {
                                Text(currency.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(currencyService.formatAmountWithFullCurrency(amount, in: currency))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(amount >= 0 ? .primary : .red)

                                Button {
                                    editContext = CashBalanceEditContext(
                                        institution: institution,
                                        currencyBalance: currencyBalance,
                                        currency: currency
                                    )
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(footer: Text(localizationManager.localizedString(for: "cashOverview.demandCash.footer"))) {
                HStack {
                    Text(localizationManager.localizedString(for: "cashOverview.demandCash.totalCash"))
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text(currencyService.formatAmount(totalDemandCash, in: mainCurrency))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(totalDemandCash >= 0 ? .primary : .red)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var fixedDepositSection: some View {
        if activeDeposits.isEmpty && maturedDeposits.isEmpty {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(localizationManager.localizedString(for: "cashOverview.fixedDeposits.noDepositsTitle"))
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(localizationManager.localizedString(for: "cashOverview.fixedDeposits.noDepositsMessage"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            if !activeDeposits.isEmpty {
                Section(header: Text(localizationManager.localizedString(for: "cashOverview.fixedDeposits.activeHeader"))) {
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
                Section(header: Text(localizationManager.localizedString(for: "cashOverview.fixedDeposits.maturedHeader"))) {
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
        }
    }

    private func loadFixedDeposits() {
        activeDeposits = FixedDepositService.shared.getActiveFixedDeposits(for: portfolio, context: viewContext)
        maturedDeposits = FixedDepositService.shared.getMaturedFixedDeposits(for: portfolio, context: viewContext)
        updateMaturityAlertState()
    }

    private func updateMaturityAlertState() {
        let maturedNames = maturedDeposits.map { $0.name ?? $0.symbol ?? "Fixed Deposit" }

        if maturedNames.isEmpty {
            hasShownMaturityAlert = false
            maturityAlertDepositNames = []
            showingMaturityAlert = false
            return
        }

        maturityAlertDepositNames = maturedNames

        if !hasShownMaturityAlert {
            showingMaturityAlert = true
            hasShownMaturityAlert = true
        }
    }

    private func refreshPortfolioAggregates() -> Error? {
        let totalCash = portfolio.getTotalCashBalanceInMainCurrency()
        portfolio.cashBalanceSafe = totalCash

        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let holdingsValue = holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return sum + cashValue
            }
            return sum + (holding.quantity * asset.currentPrice)
        }

        portfolio.totalValue = holdingsValue + totalCash

        do {
            try viewContext.save()
            portfolio.objectWillChange.send()
            return nil
        } catch {
            print("❌ Error saving portfolio aggregates after cash edit: \(error)")
            return error
        }
    }

    private func valueInMainCurrency(for deposit: Asset) -> Double {
        let depositCurrency = determineCurrency(for: deposit)
        let amount = deposit.currentPrice
        return currencyService.convertAmount(amount, from: depositCurrency, to: mainCurrency)
    }

    private func determineCurrency(for deposit: Asset) -> Currency {
        let transactions = (deposit.transactions?.allObjects as? [Transaction]) ?? []
        if let firstTransaction = transactions.first,
           let currencyCode = firstTransaction.currency,
           let currency = Currency(rawValue: currencyCode) {
            return currency
        }
        return mainCurrency
    }
}

struct CashBalanceEditSheet: View {
    let institution: Institution
    @ObservedObject var currencyBalance: PortfolioInstitutionCurrencyCash
    let currency: Currency
    let onSave: () -> Error?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var amountInput: String
    @State private var validationMessage: String?
    @FocusState private var amountFieldFocused: Bool

    init(institution: Institution,
         currencyBalance: PortfolioInstitutionCurrencyCash,
         currency: Currency,
         onSave: @escaping () -> Error?) {
        self.institution = institution
        self._currencyBalance = ObservedObject(wrappedValue: currencyBalance)
        self.currency = currency
        self.onSave = onSave
        _amountInput = State(wrappedValue: String(format: "%.2f", currencyBalance.amountSafe))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localizationManager.localizedString(for: "cashOverview.editSheet.institutionHeader"))) {
                    Text(institution.name ?? localizationManager.localizedString(for: "cashOverview.demandCash.unknownInstitution"))
                }

                Section(header: Text("\(localizationManager.localizedString(for: "cashOverview.editSheet.balanceHeader"))(\(currency.rawValue) \(currency.symbol))".uppercased())) {
                    TextField(localizationManager.localizedString(for: "cashOverview.editSheet.amountPlaceholder"), text: $amountInput)
                        .keyboardType(.decimalPad)
                        .focused($amountFieldFocused)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("\(currency.displayName) \(localizationManager.localizedString(for: "cashOverview.editSheet.cashTitle"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizationManager.localizedString(for: "cashOverview.editSheet.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(localizationManager.localizedString(for: "cashOverview.editSheet.save")) {
                        persistChanges()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    amountFieldFocused = true
                }
            }
        }
    }

    private func persistChanges() {
        let sanitizedInput = amountInput.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(sanitizedInput), value.isFinite else {
            validationMessage = localizationManager.localizedString(for: "cashOverview.editSheet.validationError")
            return
        }

        let roundedValue = (value * 100).rounded() / 100

        currencyBalance.amountSafe = roundedValue

        if let error = onSave() {
            validationMessage = "\(localizationManager.localizedString(for: "cashOverview.editSheet.saveError")) \(error.localizedDescription)"
            return
        }

        dismiss()
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "Sample Portfolio"
    portfolio.mainCurrency = "USD"

    return CashOverviewView(portfolio: portfolio)
        .environment(\.managedObjectContext, context)
}
