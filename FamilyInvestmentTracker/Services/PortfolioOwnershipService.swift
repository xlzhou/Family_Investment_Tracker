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
            print("Portfolio \(portfolio.name ?? "Unknown") has no owner ID")
            completion(nil)
            return
        }

        // Ensure we're on the main queue for consistent property access
        DispatchQueue.main.async {
            print("Getting owner name for portfolio \(portfolio.name ?? "Unknown"), ownerID: \(ownerID), currentUserID: \(self.currentUserID ?? "nil")")

            // If it's the current user, show "Me"
            if ownerID == self.currentUserID {
                print("Owner is current user, returning 'Me'")
                completion("Me")
                return
            }

            // Check cache first
            if let cachedName = self.userNameCache[ownerID] {
                print("Using cached name: \(cachedName)")
                completion(cachedName)
                return
            }

            // For other users, create a simple identifier based on owner ID
            let fallbackName = "User \(ownerID.suffix(4))"
            print("Using fallback name: \(fallbackName)")
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
        UserDefaults.standard.set(name, forKey: "UserDisplayName")

        // Update current name and cache
        if let userID = currentUserID {
            currentUserName = name
            userNameCache[userID] = name
        }
    }

    var userDisplayName: String {
        return UserDefaults.standard.string(forKey: "UserDisplayName") ?? "Me"
    }
}