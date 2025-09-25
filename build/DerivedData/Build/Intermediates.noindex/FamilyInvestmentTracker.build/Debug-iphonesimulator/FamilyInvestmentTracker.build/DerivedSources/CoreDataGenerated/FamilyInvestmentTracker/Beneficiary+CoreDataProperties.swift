//
//  Beneficiary+CoreDataProperties.swift
//  
//
//  Created by 周晓凌 on 2025/9/24.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias BeneficiaryCoreDataPropertiesSet = NSSet

extension Beneficiary {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Beneficiary> {
        return NSFetchRequest<Beneficiary>(entityName: "Beneficiary")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var percentage: Double
    @NSManaged public var insurance: Insurance?

}

extension Beneficiary : Identifiable {

}
