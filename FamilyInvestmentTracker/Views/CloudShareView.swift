import SwiftUI
import CloudKit
import CoreData

struct CloudShareView: UIViewControllerRepresentable {
    let portfolioID: NSManagedObjectID
    let container: NSPersistentCloudKitContainer
    let context: NSManagedObjectContext

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context ctx: Context) -> UICloudSharingController {
        let controller: UICloudSharingController

        if let prepared = try? fetchExistingShare() {
            controller = UICloudSharingController(share: prepared.share, container: prepared.container)
        } else {
            // Fallback to an empty share so the controller can still render, though this
            // path should not be hit if we gate presentation on an existing share.
            let placeholderRecord = CKRecord(recordType: "Portfolio")
            let placeholderShare = CKShare(rootRecord: placeholderRecord)
            controller = UICloudSharingController(share: placeholderShare, container: fallbackContainer())
        }

        controller.availablePermissions = [.allowReadWrite, .allowReadOnly]
        controller.delegate = ctx.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    private func fetchExistingShare() throws -> (share: CKShare, container: CKContainer) {
        enum ShareError: Error {
            case missingShare
        }

        var shareResult: (share: CKShare, container: CKContainer)?
        var caughtError: Error?

        context.performAndWait {
            do {
                let object = try context.existingObject(with: portfolioID)
                let name = (object.value(forKey: "name") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let titleString = (name?.isEmpty == false) ? (name ?? "Portfolio") : "Portfolio"

                if let existingShares = try? container.fetchShares(matching: [object.objectID]),
                   let existingShare = existingShares[object.objectID] {
                    if existingShare[CKShare.SystemFieldKey.title] == nil {
                        existingShare[CKShare.SystemFieldKey.title] = titleString as NSString
                    }
                    shareResult = (existingShare, resolvedContainer())
                }
            } catch {
                caughtError = error
            }
        }

        if let result = shareResult {
            return result
        }

        if let error = caughtError {
            throw error
        }

        throw ShareError.missingShare
    }

    private func resolvedContainer() -> CKContainer {
        if let identifier = container.persistentStoreDescriptions
            .first?
            .cloudKitContainerOptions?
            .containerIdentifier {
            return CKContainer(identifier: identifier)
        }

        return fallbackContainer()
    }

    private func fallbackContainer() -> CKContainer {
        CKContainer(identifier: "iCloud.com.kongkong.FamilyInvestmentTracker")
    }

    private func handleStopSharing(_ share: CKShare?) {
        let postNotShared: () -> Void = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cloudShareStatusChanged,
                                                object: self.portfolioID,
                                                userInfo: ["status": CloudShareStatus.notShared])
            }
        }

        context.perform {
            do {
                if let object = try? self.context.existingObject(with: self.portfolioID) {
                    _ = try? self.container.fetchShares(matching: [object.objectID])
                    object.managedObjectContext?.refresh(object, mergeChanges: false)
                }
            } catch {
                print("Cloud sharing stop error: \(error)")
            }
            postNotShared()
        }
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudShareView

        init(parent: CloudShareView) {
            self.parent = parent
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.handleStopSharing(csc.share)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Portfolio" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Cloud sharing save error: \(error)")
        }
    }
}
