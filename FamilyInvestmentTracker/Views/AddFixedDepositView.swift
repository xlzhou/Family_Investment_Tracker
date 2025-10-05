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
    @State private var errorMessage = ""

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
        Calendar.current.date(byAdding: .month, value: termMonths, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Fixed Deposit Details")) {
                    TextField("Deposit Name", text: $depositName)
                    TextField("Symbol (optional)", text: $symbol)

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                }

                Section(header: Text("Term & Interest")) {
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
                }

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

        // Auto-generate name based on term
        if depositName.isEmpty {
            let termString: String
            if termMonths >= 12 {
                let years = termMonths / 12
                termString = "\(years)-Year"
            } else {
                termString = "\(termMonths)-Month"
            }
            depositName = "\(termString) Fixed Deposit"
        }
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
                context: viewContext
            )

            // Create the initial deposit transaction
            let transaction = Transaction(context: viewContext)
            transaction.id = UUID()
            transaction.createdAt = Date()
            transaction.transactionDate = Date()
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

            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to create fixed deposit: \(error.localizedDescription)"
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
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let portfolio = Portfolio(context: context)
    portfolio.name = "Test Portfolio"
    portfolio.mainCurrency = "USD"

    return AddFixedDepositView(portfolio: portfolio)
        .environment(\.managedObjectContext, context)
}