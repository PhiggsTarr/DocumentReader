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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

