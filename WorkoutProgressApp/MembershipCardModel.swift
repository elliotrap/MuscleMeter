//
//  KeyCardModel.swift
//  WorkoutProgressApp
//
//  Created by Elliot Rapp on 2/26/25.
//

import CloudKit
import UIKit

struct MembershipCard: Identifiable {
    var id: CKRecord.ID?
    var barcodeValue: String?
    var barcodeImage: UIImage?
    
    // Create a MembershipCard from a CKRecord.
    init(record: CKRecord) {
        self.id = record.recordID
        self.barcodeValue = record["barcodeValue"] as? String
        if let asset = record["barcodeImage"] as? CKAsset,
           let fileURL = asset.fileURL,
           let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            self.barcodeImage = image
        } else {
            self.barcodeImage = nil
        }
    }
    
    // For creating a new instance.
    init(id: CKRecord.ID? = nil, barcodeValue: String?, barcodeImage: UIImage?) {
        self.id = id
        self.barcodeValue = barcodeValue
        self.barcodeImage = barcodeImage
    }
}
