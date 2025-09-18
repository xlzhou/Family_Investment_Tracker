import SwiftUI
import CloudKit
import CoreData

struct CloudShareView: UIViewControllerRepresentable {
    let portfolioID: NSManagedObjectID
    let container: NSPersistentCloudKitContainer
    let context: NSManagedObjectContext

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context ctx: Context) -> UICloudSharingController {
        // Create a simple share for now
        let record = CKRecord(recordType: "Portfolio")
        let share = CKShare(rootRecord: record)
        let ckContainer = CKContainer(identifier: "iCloud.com.kongkong.FamilyInvestmentTracker")

        let controller = UICloudSharingController(share: share, container: ckContainer)
        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = ctx.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("Stopped sharing")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "Portfolio"
        }
    }
}
