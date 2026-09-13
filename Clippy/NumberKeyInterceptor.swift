//
//  NumberKeyInterceptor.swift
//  Clippy
//
//  Temporarily consumes plain number keys while inline clipboard selection is visible.
//

import AppKit
import Carbon.HIToolbox

/// Intercepts 0–9 before the focused app receives them, then reports each digit.
/// It is deliberately active only while Clippy's inline picker is visible.
@MainActor
final class NumberKeyInterceptor {

    private let onDigit: (Int) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    init(onDigit: @escaping (Int) -> Void) {
        self.onDigit = onDigit
    }

    /// Starts consuming the number keys. Returns false when macOS declines the event tap.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let interceptor = Unmanaged<NumberKeyInterceptor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async {
                        interceptor.reenable()
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown,
                      let digit = NumberKeyInterceptor.digit(
                        for: event.getIntegerValueField(.keyboardEventKeycode)
                      ) else {
                    return Unmanaged.passUnretained(event)
                }

                DispatchQueue.main.async {
                    interceptor.onDigit(digit)
                }
                // Suppress the digit so it is not also inserted in the target field.
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
    }

    private func reenable() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private static func digit(for keyCode: Int64) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_0: return 0
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        default: return nil
        }
    }
}
