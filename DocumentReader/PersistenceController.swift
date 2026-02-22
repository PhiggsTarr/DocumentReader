//
//  PersistenceController.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/13/26.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        // ⚠️ Change this to your .xcdatamodeld name
        // If your file is DocumentReader.xcdatamodeld then the name is "DocumentReader"
        container = NSPersistentContainer(name: "DocumentReaderModel")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}


