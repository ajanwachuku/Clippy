//
//  HotKeyCenter.swift
//  Clippy
//
//  System-wide hot keys via Carbon's RegisterEventHotKey.
//
//  Chosen over an NSEvent global monitor because it requires no Accessibility /
//  Input Monitoring permission and it consumes the keystroke, so the frontmost
//  app never also receives it. That matters twice here: the toggle hotkey must
//  work before the user has granted any permissions, and Escape-to-close must
//  not simultaneously send Escape to the app being worked in.
//

import Carbon.HIToolbox

/// Four-char code identifying Clippy's hot keys ("CLPY").
private let hotKeySignature: OSType = 0x434C_5059

/// Registers and dispatches global hot keys. All use is on the main actor;
/// Carbon delivers the events on the main thread.
@MainActor
final class HotKeyCenter {

    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installedEventHandler = false

    /// Registers `handler` to fire whenever the key combination is pressed in any app.
    ///
    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - carbonModifiers: a combination of `cmdKey`, `optionKey`, `shiftKey`,
    ///     `controlKey` — or `0` for an unmodified key.
    /// - Returns: an identifier for `unregister`, or `nil` if registration failed
    ///   (e.g. the combination is taken by the system).
    @discardableResult
    func register(keyCode: Int, carbonModifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(carbonModifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }

        handlers[id] = handler
        refs[id] = ref
        return id
    }

    /// Removes a hot key registered with `register`. Safe to call with a stale id.
    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    private func dispatch(_ id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard !installedEventHandler else { return }
        installedEventHandler = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches on the main thread.
            MainActor.assumeIsolated {
                HotKeyCenter.shared.dispatch(hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
