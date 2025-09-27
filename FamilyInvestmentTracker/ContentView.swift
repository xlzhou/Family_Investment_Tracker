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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // App completely backgrounded - start logout timer
                authManager.handleAppDidEnterBackground()
            case .inactive:
                // App covered by system UI (Control Center, AutoFill, etc) - no action
                // This prevents logout during password AutoFill
                break
            case .active:
                // App returned to foreground - always cancel logout timer
                authManager.handleAppWillEnterForeground()
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
