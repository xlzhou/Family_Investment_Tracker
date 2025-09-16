import SwiftUI
import CoreData

struct PortfolioSettingsView: View {
    let portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var portfolioName: String
    @State private var selectedMainCurrency: Currency
    
    init(portfolio: Portfolio) {
        self.portfolio = portfolio
        _portfolioName = State(initialValue: portfolio.name ?? "")
        _selectedMainCurrency = State(initialValue: Currency(rawValue: portfolio.mainCurrency ?? "USD") ?? .usd)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Portfolio Information")) {
                    TextField("Portfolio Name", text: $portfolioName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
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
                
                Section(header: Text("Statistics")) {
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
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(portfolioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveSettings() {
        portfolio.name = portfolioName.trimmingCharacters(in: .whitespacesAndNewlines)
        portfolio.mainCurrency = selectedMainCurrency.rawValue
        portfolio.updatedAt = Date()
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving portfolio settings: \(error)")
        }
    }
}

#Preview {
    PortfolioSettingsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}