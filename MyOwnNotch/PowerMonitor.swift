//
//  PowerMonitor.swift
//  MyOwnNotch
//
//  Notificações de mudança de fonte de energia (IOPSNotificationCreateRunLoopSource),
//  substituindo o polling de bateria.
//

import Foundation
import IOKit.ps

final class PowerMonitor {
    private var source: CFRunLoopSource?
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        stop()
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handler?()
        }
        guard let src = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    }

    func stop() {
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        source = nil
        handler = nil
    }

    deinit { stop() }
}
