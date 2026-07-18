//
//  LoginItem.swift
//  Clippy
//
//  Launch-at-login control backed by SMAppService.
//

import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the launch-at-login toggle.
enum LoginItem {

    /// Whether Clippy is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters Clippy as a login item.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Non-fatal: the toggle simply won't take effect this time.
        }
    }
}
