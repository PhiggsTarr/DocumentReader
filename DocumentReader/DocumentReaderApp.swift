//
//  DocumentReaderApp.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/10/26.
//

import SwiftUI

@main
struct DocumentReaderApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(purchaseManager)
                .environmentObject(store) 
        }
    }
}
