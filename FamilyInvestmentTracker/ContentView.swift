import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingMigration = false
    @State private var migrationChecked = false

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if migrationChecked && showingMigration {
                    FixedDepositMigrationView()
                } else {
                    PortfolioListView()
                }
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
        .onAppear {
            checkMigrationStatus()
        }
    }

    private func checkMigrationStatus() {
        guard !migrationChecked else { return }

        DispatchQueue.main.async {
            let shouldShowMigration = FixedDepositMigrationService.shared.shouldShowMigrationPrompt(context: viewContext)
            showingMigration = shouldShowMigration
            migrationChecked = true
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
