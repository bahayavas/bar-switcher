import Carbon

/// Carbon RegisterEventHotKey ile global kısayollar — Accessibility izni gerektirmez.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// Başka bir uygulama aynı kısayolu almışsa false döner.
    @discardableResult
    static func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x42525357) /* BRSW */, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        handlers[id] = handler
        refs[id] = ref
        return true
    }

    static func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKeys.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
