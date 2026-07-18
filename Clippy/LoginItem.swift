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
    ///
    /// - Returns: whether the change took effect, so the UI can revert its toggle
    ///   instead of showing a state that isn't true.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
