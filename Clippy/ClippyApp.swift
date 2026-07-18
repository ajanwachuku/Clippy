//
//  ClippyApp.swift
//  Clippy
//
//  Created by Peter AjaNwachuku on 18/07/2026.
//

import SwiftUI

@main
struct ClippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only agent app: no main window. The status item and popover
        // are created by AppDelegate. An empty Settings scene satisfies the
        // App protocol without showing any window.
        Settings {
            EmptyView()
        }
    }
}
