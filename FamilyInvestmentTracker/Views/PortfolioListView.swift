import SwiftUI
import Foundation
import CoreData

struct PortfolioListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthenticationManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Portfolio.name, ascending: true)],
        animation: .default)
    private var portfolios: FetchedResults<Portfolio>
    
    @State private var showingAddPortfolio = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Investment Portfolios")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Total Value: " + Formatters.decimal(totalPortfolioValue))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                    }

                    Button(action: {
                        authManager.logout()
                    }) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                    }
                }
            }
            .padding()
                
                // Portfolio Cards
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 20) {
                        ForEach(portfolios, id: \.objectID) { portfolio in
                            NavigationLink(destination: PortfolioDashboardView(portfolio: portfolio)) {
                                PortfolioCardView(portfolio: portfolio)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Add Portfolio Button
                        Button(action: {
                            showingAddPortfolio = true
                        }) {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                
                                Text("Add Portfolio")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(15)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [10]))
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingAddPortfolio) {
            AddPortfolioView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(authManager)
        }
        .onAppear {
            // Clean up existing default portfolios on first launch
            cleanupDefaultPortfolios()
            // Ensure current user ID is fetched
            PortfolioOwnershipService.shared.fetchCurrentUserID()
        }
    }
    
    private var totalPortfolioValue: Double {
        portfolios.reduce(0.0) { partial, portfolio in
            let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
            let holdingsValue = holdings.reduce(0.0) { sum, holding in
                guard let asset = holding.asset else { return sum }
                if asset.assetType == AssetType.insurance.rawValue {
                    let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                    return sum + cashValue
                }
                return sum + (holding.quantity * asset.currentPrice)
            }
            return partial + holdingsValue + portfolio.cashBalanceSafe
        }
    }

    private func cleanupDefaultPortfolios() {
        // Only run this cleanup once
        let hasCleanedUp = UserDefaults.standard.bool(forKey: "HasCleanedUpDefaultPortfolios")
        guard !hasCleanedUp else { return }

        let defaultNames = ["Jerry", "Carol", "Ray", "Family"]

        // Find and delete portfolios with default names that have no owner
        for portfolio in portfolios {
            if let name = portfolio.name,
               defaultNames.contains(name),
               portfolio.ownerID == nil {

                // Delete all related data first
                let transactions = (portfolio.transactions?.allObjects as? [Transaction]) ?? []
                let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []

                transactions.forEach(viewContext.delete)
                holdings.forEach(viewContext.delete)

                // Delete the portfolio itself
                viewContext.delete(portfolio)
            }
        }

        do {
            try viewContext.save()
            UserDefaults.standard.set(true, forKey: "HasCleanedUpDefaultPortfolios")
            print("Cleaned up default portfolios")
        } catch {
            print("Error cleaning up default portfolios: \(error)")
        }
    }

}

struct PortfolioCardView: View {
    @ObservedObject var portfolio: Portfolio
    @StateObject private var ownershipService = PortfolioOwnershipService.shared
    @State private var ownerName: String?
    
    private var currentValue: Double {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let holdingsValue = holdings.reduce(0.0) { sum, holding in
            guard let asset = holding.asset else { return sum }
            if asset.assetType == AssetType.insurance.rawValue {
                let cashValue = holding.value(forKey: "cashValue") as? Double ?? 0
                return sum + cashValue
            }
            return sum + (holding.quantity * asset.currentPrice)
        }
        return holdingsValue + portfolio.cashBalanceSafe
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(portfolio.name ?? "Unknown")
                    .font(.title2)
                    .fontWeight(.semibold)

                if ownershipService.isCurrentUserOwner(of: portfolio) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }

                if let ownerName = ownerName {
                    Text("Owner: \(ownerName)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Value")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(Formatters.currency(currentValue))
                    .font(.title3)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Holdings")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(portfolio.holdings?.count ?? 0)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Transactions")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(portfolio.transactions?.count ?? 0)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .onAppear {
            refreshOwnerName()
        }
        .onReceive(ownershipService.$currentUserID) { userID in
            // Refresh owner name when current user ID changes
            print("Portfolio card received user ID update: \(userID ?? "nil")")
            refreshOwnerName()
        }
    }

    private func refreshOwnerName() {
        ownershipService.getOwnerName(for: portfolio) { name in
            ownerName = name
        }
    }
}

#Preview {
    PortfolioListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthenticationManager())
}
