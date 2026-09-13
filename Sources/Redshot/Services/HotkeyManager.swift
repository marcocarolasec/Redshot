import Carbon.HIToolbox
import Foundation

/// Atajos globales con la API Carbon (RegisterEventHotKey). No requiere Accesibilidad.
final class HotkeyManager {
    static let shared = HotkeyManager()

    struct Hotkey {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5356_4C54 // "SVLT"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hotkeyID.id]?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotkeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        handlers[id] = action
        refs.append(ref)
        return true
    }

    func unregisterAll() {
        for case let ref? in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }
}

// MARK: - Códigos de tecla (teclado ANSI)

enum Key {
    static let v: UInt32 = 9
    static let s: UInt32 = 1
    static let w: UInt32 = 13
    static let f: UInt32 = 3
    static let digits: [UInt32] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25] // 0...9

    static let ctrlCmd = UInt32(controlKey | cmdKey)
    static let ctrlCmdShift = UInt32(controlKey | cmdKey | shiftKey)
}
