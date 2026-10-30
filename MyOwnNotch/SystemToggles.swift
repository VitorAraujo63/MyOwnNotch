//
//  SystemToggles.swift
//  MyOwnNotch
//
//  "Manter acordado" (IOPMAssertion), monitor de Caps Lock e helpers de energia.
//

import AppKit
import IOKit.pwr_mgt

// MARK: - Manter acordado

/// Impede a tela/sistema de dormir por inatividade enquanto existir. Libera no deinit.
final class StayAwakeAssertion {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private(set) var isActive = false

    /// Retorna false se o sistema recusar a assertion.
    @discardableResult
    func acquire() -> Bool {
        guard !isActive else { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MyOwnNotch: Manter acordado" as CFString,
            &assertionID)
        isActive = (result == kIOReturnSuccess)
        return isActive
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        isActive = false
    }

    deinit { if isActive { IOPMAssertionRelease(assertionID) } }
}

// MARK: - Caps Lock

/// Observa o Caps Lock sem monitor global (evita prompt de Input Monitoring): monitor local de
/// `.flagsChanged` + verificação leve a cada 0.5 s via CGEventSource.flagsState (não exige
/// permissão). Tudo é desligado em `stop()` (ex.: durante sleep ou showCapsLock desligado).
@MainActor
final class CapsLockMonitor {
    private(set) var isOn: Bool = CapsLockMonitor.currentState()
    private var onChange: ((Bool) -> Void)?
    private var localMonitor: Any?
    private var timer: Timer?
    var isRunning: Bool { timer != nil }

    nonisolated static func currentState() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    func start(_ onChange: @escaping (Bool) -> Void) {
        stop()
        self.onChange = onChange
        update(Self.currentState())
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.update(Self.currentState()) }
            return event
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.update(Self.currentState()) }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        localMonitor = nil
        timer?.invalidate(); timer = nil
    }

    private func update(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        onChange?(on)
    }
}

// MARK: - Low Power Mode

enum LowPowerMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    static let didChange = Notification.Name.NSProcessInfoPowerStateDidChange
}
