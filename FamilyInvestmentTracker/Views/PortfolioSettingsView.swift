import SwiftUI
import CoreData

struct PortfolioSettingsView: View {
    let portfolio: Portfolio
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var portfolioName: String
    @State private var selectedMainCurrency: Currency
    @State private var newInstitutionName: String = ""
    @State private var editingInstitution: Institution?
    @State private var editingInstitutionName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var institutionToDelete: Institution?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Institution.name, ascending: true)],
        animation: .default
    ) private var institutions: FetchedResults<Institution>

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
                                    institutionToDelete = institution
                                    showingDeleteConfirmation = true
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
        .alert("Delete Institution", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                institutionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let institution = institutionToDelete {
                    deleteInstitution(institution)
                }
                institutionToDelete = nil
            }
        } message: {
            if let institution = institutionToDelete {
                Text("Are you sure you want to delete \"\(institution.name ?? "this institution")\"? This action cannot be undone.")
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
}

#Preview {
    PortfolioSettingsView(portfolio: PersistenceController.preview.container.viewContext.registeredObjects.first(where: { $0 is Portfolio }) as! Portfolio)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
