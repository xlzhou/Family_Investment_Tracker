import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                PortfolioListView()
            } else {
                AuthenticationView()
            }
        }
        .environmentObject(authManager)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                authManager.logout()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
