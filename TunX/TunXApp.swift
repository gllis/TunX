//
//  TunXApp.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import SwiftUI

@main
struct TunXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
