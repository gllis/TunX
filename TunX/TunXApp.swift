//
//  TunXApp.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI
import SwiftData

@main
struct TunXApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Tunnel.self,
            ForwardRule.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        Window("TunX", id: "main") {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentSize)

        MenuBarExtra("TunX", systemImage: "network") {
            MenuBarView()
        }
        .modelContainer(sharedModelContainer)
        .menuBarExtraStyle(.window)
    }
}
