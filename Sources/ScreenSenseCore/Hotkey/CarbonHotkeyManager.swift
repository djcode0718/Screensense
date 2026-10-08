import Foundation
import Carbon
import AppKit

public enum HotkeyError: LocalizedError, Sendable {
    case registrationFailed(OSStatus)
    case eventHandlerInstallationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Failed to register global hotkey (OSStatus: \(status))."
        case .eventHandlerInstallationFailed(let status):
            return "Failed to install Carbon event handler (OSStatus: \(status))."
        }
    }
}

/// Global Hotkey Manager using macOS Carbon Event APIs
public final class CarbonHotkeyManager: HotkeyManagerProtocol, @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var triggerHandler: (@Sendable () -> Void)?
    private let lock = NSLock()

    // Default: Option + Shift + Space
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyID: UInt32 = 1001
    private let signature: OSType = 0x53435253 // 'SCRS' (ScreenSense)

    public var isRegistered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hotKeyRef != nil
    }

    /// - Parameters:
    ///   - keyCode: Carbon key code (e.g. 49 / 0x31 for Space, 9 for 'V')
    ///   - modifiers: Carbon modifier mask (e.g. optionKey | shiftKey)
    public init(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey | shiftKey)
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    deinit {
        unregister()
    }

    public func register(handler: @escaping @Sendable () -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        unregisterInternal()
        self.triggerHandler = handler

        // Install event handler on application target
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (handlerCallRef, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if err == noErr {
                    let manager = Unmanaged<CarbonHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.handleHotKeyTriggered(id: hotKeyID.id)
                    return noErr
                }

                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            ScreenSenseLogger.hotkey.error("Failed to install Carbon event handler: \(status)")
            throw HotkeyError.eventHandlerInstallationFailed(status)
        }

        let hotKeyIDStruct = EventHotKeyID(signature: signature, id: hotKeyID)
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard regStatus == noErr else {
            ScreenSenseLogger.hotkey.error("Failed to register Carbon hotkey: \(regStatus)")
            if let handlerRef = eventHandlerRef {
                RemoveEventHandler(handlerRef)
                eventHandlerRef = nil
            }
            throw HotkeyError.registrationFailed(regStatus)
        }

        ScreenSenseLogger.hotkey.info("Global hotkey registered successfully (KeyCode: \(self.keyCode), Modifiers: \(self.modifiers))")
    }

    public func unregister() {
        lock.lock()
        defer { lock.unlock() }
        unregisterInternal()
    }

    private func unregisterInternal() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            self.eventHandlerRef = nil
        }
        triggerHandler = nil
        ScreenSenseLogger.hotkey.info("Global hotkey unregistered")
    }

    private func handleHotKeyTriggered(id: UInt32) {
        guard id == hotKeyID else { return }
        ScreenSenseLogger.hotkey.info("Global hotkey triggered!")
        triggerHandler?()
    }
}
