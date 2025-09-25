//
//  InstitutionAssetAvailability+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/24.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias InstitutionAssetAvailabilityCoreDataPropertiesSet = NSSet

extension InstitutionAssetAvailability {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InstitutionAssetAvailability> {
        return NSFetchRequest<InstitutionAssetAvailability>(entityName: "InstitutionAssetAvailability")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var lastTransactionDate: Date?
    @NSManaged public var asset: Asset?
    @NSManaged public var institution: Institution?

}

extension InstitutionAssetAvailability : Identifiable {

}
