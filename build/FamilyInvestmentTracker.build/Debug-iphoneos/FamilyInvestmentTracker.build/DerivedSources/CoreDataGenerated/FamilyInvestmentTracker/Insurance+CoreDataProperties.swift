//
//  Insurance+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/10/7.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias InsuranceCoreDataPropertiesSet = NSSet

extension Insurance {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Insurance> {
        return NSFetchRequest<Insurance>(entityName: "Insurance")
    }

    @NSManaged public var additionalPaymentAmount: Double
    @NSManaged public var basicInsuredAmount: Double
    @NSManaged public var canWithdrawPremiums: Bool
    @NSManaged public var contactNumber: String?
    @NSManaged public var coverageExpirationDate: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var deathBenefit: Double
    @NSManaged public var estimatedMaturityBenefit: Double
    @NSManaged public var hasSupplementaryInsurance: Bool
    @NSManaged public var id: UUID?
    @NSManaged public var insuranceType: String?
    @NSManaged public var insuredPerson: String?
    @NSManaged public var isParticipating: Bool
    @NSManaged public var maturityBenefitRedemptionDate: Date?
    @NSManaged public var maxWithdrawalPercentage: Double
    @NSManaged public var policyholder: String?
    @NSManaged public var premiumPaymentStatus: String?
    @NSManaged public var premiumPaymentTerm: Int32
    @NSManaged public var premiumPaymentType: String?
    @NSManaged public var singlePremium: Double
    @NSManaged public var firstDiscountedPremium: Double
    @NSManaged public var totalPremium: Double
    @NSManaged public var asset: Asset?
    @NSManaged public var beneficiaries: NSSet?

}

// MARK: Generated accessors for beneficiaries
extension Insurance {

    @objc(addBeneficiariesObject:)
    @NSManaged public func addToBeneficiaries(_ value: Beneficiary)

    @objc(removeBeneficiariesObject:)
    @NSManaged public func removeFromBeneficiaries(_ value: Beneficiary)

    @objc(addBeneficiaries:)
    @NSManaged public func addToBeneficiaries(_ values: NSSet)

    @objc(removeBeneficiaries:)
    @NSManaged public func removeFromBeneficiaries(_ values: NSSet)

}

extension Insurance : Identifiable {

}
