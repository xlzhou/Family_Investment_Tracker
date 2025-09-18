import Foundation
import CloudKit
import CoreData

enum CloudShareStatus {
    case shared
    case notShared
}

enum CloudShareError: Error {
    case missingShare
}

class CloudShareManager {
    static let shared = CloudShareManager()

    private init() {}

    func existingShare(for objectID: NSManagedObjectID,
                       in context: NSManagedObjectContext,
                       container: NSPersistentCloudKitContainer) -> CKShare? {
        var share: CKShare?
        context.performAndWait {
            if let shares: [NSManagedObjectID: CKShare] = try? container.fetchShares(matching: [objectID]) {
                share = shares[objectID]
            }
        }
        return share
    }

    func currentStatus(for objectID: NSManagedObjectID,
                       in context: NSManagedObjectContext,
                       container: NSPersistentCloudKitContainer) -> CloudShareStatus {
        existingShare(for: objectID, in: context, container: container) == nil ? .notShared : .shared
    }

    func createShare(for objectID: NSManagedObjectID,
                     in context: NSManagedObjectContext,
                     container: NSPersistentCloudKitContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.perform {
                do {
                    let object = try context.existingObject(with: objectID)
                    let name = (object.value(forKey: "name") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let titleString = (name?.isEmpty == false) ? (name ?? "Portfolio") : "Portfolio"

                    container.share([object], to: nil) { _, share, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard let share = share else {
                            continuation.resume(throwing: CloudShareError.missingShare)
                            return
                        }

                        if share[CKShare.SystemFieldKey.title] == nil {
                            share[CKShare.SystemFieldKey.title] = titleString as NSString
                        }
                        share.publicPermission = .none

                        context.perform {
                            if context.hasChanges {
                                do {
                                    try context.save()
                                } catch {
                                    continuation.resume(throwing: error)
                                    return
                                }
                            }

                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .cloudShareStatusChanged,
                                                                object: objectID,
                                                                userInfo: ["status": CloudShareStatus.shared])
                            }
                            continuation.resume(returning: ())
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension Notification.Name {
    static let cloudShareStatusChanged = Notification.Name("CloudShareStatusChanged")
}
