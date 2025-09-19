import Foundation
import CloudKit
import CoreData

class PortfolioOwnershipService: ObservableObject {
    static let shared = PortfolioOwnershipService()

    @Published var currentUserID: String?
    @Published var currentUserName: String?
    private let container = CKContainer(identifier: "iCloud.com.kongkong.FamilyInvestmentTracker")

    // Cache for user names to avoid repeated CloudKit calls
    private var userNameCache: [String: String] = [:]

    private init() {
        fetchCurrentUserID()
    }

    func fetchCurrentUserID() {
        container.fetchUserRecordID { [weak self] recordID, error in
            DispatchQueue.main.async {
                if let recordID = recordID {
                    print("CloudKit user ID fetched: \(recordID.recordName)")
                    self?.currentUserID = recordID.recordName
                    self?.fetchCurrentUserName()
                    // Force UI update by triggering objectWillChange
                    self?.objectWillChange.send()
                } else if let error = error {
                    print("Error fetching user ID: \(error)")
                }
            }
        }
    }

    private func fetchCurrentUserName() {
        guard let userID = currentUserID else { return }

        // Check cache first
        if let cachedName = userNameCache[userID] {
            DispatchQueue.main.async {
                self.currentUserName = cachedName
            }
            return
        }

        // For current user, try to get display name from UserDefaults or use "Me"
        DispatchQueue.main.async {
            let displayName = UserDefaults.standard.string(forKey: "UserDisplayName") ?? "Me"
            self.currentUserName = displayName
            self.userNameCache[userID] = displayName
        }
    }

    func getOwnerName(for portfolio: Portfolio, completion: @escaping (String?) -> Void) {
        guard let ownerID = portfolio.ownerID else {
            print("🔧 OwnershipService getOwnerName: Portfolio \(portfolio.name ?? "Unknown") has no owner ID")
            completion(nil)
            return
        }

        // Ensure we're on the main queue for consistent property access
        DispatchQueue.main.async {
            print("🔧 OwnershipService getOwnerName: Getting owner name for portfolio \(portfolio.name ?? "Unknown"), ownerID: \(ownerID), currentUserID: \(self.currentUserID ?? "nil")")

            // If it's the current user, return the current user's display name
            if ownerID == self.currentUserID {
                let displayName = self.userDisplayName
                print("🔧 OwnershipService getOwnerName: Owner is current user, returning '\(displayName)'")
                completion(displayName)
                return
            }

            // Check cache first
            if let cachedName = self.userNameCache[ownerID] {
                print("🔧 OwnershipService getOwnerName: Using cached name: \(cachedName)")
                completion(cachedName)
                return
            }

            // For other users, create a simple identifier based on owner ID
            let fallbackName = "User \(ownerID.suffix(4))"
            print("🔧 OwnershipService getOwnerName: Using fallback name: \(fallbackName)")
            self.userNameCache[ownerID] = fallbackName
            completion(fallbackName)
        }
    }

    func setOwnerForNewPortfolio(_ portfolio: Portfolio) {
        if let userID = currentUserID {
            portfolio.ownerID = userID
        }
    }

    func isCurrentUserOwner(of portfolio: Portfolio) -> Bool {
        guard let currentUserID = currentUserID,
              let portfolioOwnerID = portfolio.ownerID else {
            return false
        }
        return currentUserID == portfolioOwnerID
    }

    func canDeletePortfolio(_ portfolio: Portfolio) -> Bool {
        return isCurrentUserOwner(of: portfolio)
    }

    func canSharePortfolio(_ portfolio: Portfolio) -> Bool {
        return isCurrentUserOwner(of: portfolio)
    }

    func setUserDisplayName(_ name: String) {
        print("🔧 OwnershipService setUserDisplayName: Called with name = '\(name)'")
        print("🔧 OwnershipService setUserDisplayName: currentUserID = '\(currentUserID ?? "nil")'")
        print("🔧 OwnershipService setUserDisplayName: Previous currentUserName = '\(currentUserName ?? "nil")'")

        UserDefaults.standard.set(name, forKey: "UserDisplayName")
        print("🔧 OwnershipService setUserDisplayName: Saved to UserDefaults")

        // Update current name and cache
        if let userID = currentUserID {
            currentUserName = name
            userNameCache[userID] = name
            print("🔧 OwnershipService setUserDisplayName: Updated currentUserName and cache")

            // Trigger UI update by publishing the change
            DispatchQueue.main.async {
                print("🔧 OwnershipService setUserDisplayName: Sending objectWillChange")
                self.objectWillChange.send()
            }
        } else {
            print("🔧 OwnershipService setUserDisplayName: No currentUserID, skipping cache update")
        }

        // Verify the save
        let saved = UserDefaults.standard.string(forKey: "UserDisplayName")
        print("🔧 OwnershipService setUserDisplayName: Verification - UserDefaults now contains: '\(saved ?? "nil")'")
    }

    var userDisplayName: String {
        let name = UserDefaults.standard.string(forKey: "UserDisplayName") ?? "Me"
        print("🔧 OwnershipService userDisplayName: Returning '\(name)'")
        return name
    }
}