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
            createDefaultPortfoliosIfNeeded()
        }
    }
    
    private var totalPortfolioValue: Double {
        portfolios.reduce(0.0) { partial, portfolio in
            let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
            let holdingsValue = holdings.reduce(0.0) { sum, holding in
                guard let asset = holding.asset else { return sum }
                return sum + (holding.quantity * asset.currentPrice)
            }
            return partial + holdingsValue + portfolio.cashBalanceSafe
        }
    }
    
    private func createDefaultPortfoliosIfNeeded() {
        if portfolios.isEmpty {
            let defaultNames = ["Jerry", "Carol", "Ray", "Family"]
            
            for name in defaultNames {
                let portfolio = Portfolio(context: viewContext)
                portfolio.id = UUID()
                portfolio.name = name
                portfolio.createdAt = Date()
                portfolio.updatedAt = Date()
                portfolio.totalValue = 0.0
                portfolio.enforcesCashDisciplineEnabled = true
            }
            
            do {
                try viewContext.save()
            } catch {
                print("Error creating default portfolios: \(error)")
            }
        }
    }
}

struct PortfolioCardView: View {
    @ObservedObject var portfolio: Portfolio
    
    private var currentValue: Double {
        let holdings = (portfolio.holdings?.allObjects as? [Holding]) ?? []
        let holdingsValue = holdings.reduce(0.0) { sum, h in
            guard let asset = h.asset else { return sum }
            return sum + (h.quantity * asset.currentPrice)
        }
        return holdingsValue + portfolio.cashBalanceSafe
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(portfolio.name ?? "Unknown")
                    .font(.title2)
                    .fontWeight(.semibold)
                
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
    }
}

#Preview {
    PortfolioListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthenticationManager())
}
