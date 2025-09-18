import SwiftUI
import CoreData

struct AddPortfolioView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var portfolioName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Portfolio Details")) {
                    TextField("Portfolio Name", text: $portfolioName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section(footer: Text("You can create separate portfolios for each family member or investment strategy.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Add Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePortfolio()
                    }
                    .disabled(portfolioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func savePortfolio() {
        let portfolio = Portfolio(context: viewContext)
        portfolio.id = UUID()
        portfolio.name = portfolioName.trimmingCharacters(in: .whitespacesAndNewlines)
        portfolio.createdAt = Date()
        portfolio.updatedAt = Date()
        portfolio.totalValue = 0.0

        // Set the current user as the owner
        PortfolioOwnershipService.shared.setOwnerForNewPortfolio(portfolio)
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving portfolio: \(error)")
        }
    }
}

#Preview {
    AddPortfolioView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}