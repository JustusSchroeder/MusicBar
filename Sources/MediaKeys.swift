import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Listens for headset / keyboard play-pause. Only consumes the event when
/// nothing else is using audio and Spotify is not already running.
final class MediaKeys {
    static let shared = MediaKeys()

    private var tap: CFMachPort?
    private let playKey: Int32 = 16 // NX_KEYTYPE_PLAY

    func start() {
        promptAccessibilityIfNeeded()
        guard tap == nil else { return }

        let systemDefined = CGEventType(rawValue: 14)! // NSEvent.EventType.systemDefined
        let mask = CGEventMask(1 << systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, _ in
                MediaKeys.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        ) else {
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func promptAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = MediaKeys.shared.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyCode == MediaKeys.shared.playKey, isKeyDown else {
            return Unmanaged.passUnretained(event)
        }

        guard AudioActivity.shouldClaimIdlePlayKey() else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            Task { await AppModel.shared.startFromHeadset() }
        }
        return nil
    }
}
