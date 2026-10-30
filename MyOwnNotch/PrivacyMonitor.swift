//
//  PrivacyMonitor.swift
//  MyOwnNotch
//
//  Detecta uso de câmera (CoreMediaIO) e microfone (CoreAudio) consultando apenas
//  o estado "IsRunningSomewhere" dos dispositivos. Não captura mídia, portanto
//  não requer permissão TCC de câmera/microfone.
//

import CoreAudio
import CoreMediaIO
import Combine
import Foundation

@MainActor
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraInUse = false
    @Published private(set) var micInUse = false

    private var running = false
    private let listenerQueue = DispatchQueue(label: "MyOwnNotch.PrivacyMonitor")

    // CoreAudio
    private var audioDeviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var audioListListener: AudioObjectPropertyListenerBlock?

    // CoreMediaIO
    private var camDeviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var camListListener: CMIOObjectPropertyListenerBlock?

    // Fallback de polling (somente se algum listener falhar)
    private var pollTimer: Timer?

    init() {}

    // MARK: - Ciclo de vida

    func start() {
        guard !running else { return }
        running = true
        var needsPolling = false
        if !registerAudio() { needsPolling = true }
        if !registerCamera() { needsPolling = true }
        recompute()
        if needsPolling { startPolling() }
    }

    func stop() {
        guard running else { return }
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        unregisterAudio()
        unregisterCamera()
        cameraInUse = false
        micInUse = false
    }

    private func startPolling() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recompute() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func recompute() {
        guard running else { return }
        let mic = audioDeviceListeners.keys.contains { Self.audioRunning($0) }
            || (audioListListener == nil && Self.inputDevices().contains { Self.audioRunning($0) })
        let cam = camDeviceListeners.keys.contains { Self.camRunning($0) }
            || (camListListener == nil && Self.cameraDevices().contains { Self.camRunning($0) })
        if mic != micInUse { micInUse = mic }
        if cam != cameraInUse { cameraInUse = cam }
    }

    // MARK: - CoreAudio

    private static var audioDevicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static var audioRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func inputDevices() -> [AudioObjectID] {
        var addr = audioDevicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.filter { hasInput($0) }
    }

    private static func hasInput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func audioRunning(_ id: AudioObjectID) -> Bool {
        var addr = audioRunningAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    /// Retorna false se não foi possível registrar o listener da lista.
    private func registerAudio() -> Bool {
        let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.syncAudioDevices() }
        }
        var addr = Self.audioDevicesAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue, listBlock)
        guard status == noErr else { return false }
        audioListListener = listBlock
        syncAudioDevices()
        return true
    }

    private func syncAudioDevices() {
        guard running else { return }
        let current = Set(Self.inputDevices())
        let registered = Set(audioDeviceListeners.keys)

        for id in registered.subtracting(current) {
            if let block = audioDeviceListeners.removeValue(forKey: id) {
                var addr = Self.audioRunningAddress
                AudioObjectRemovePropertyListenerBlock(id, &addr, listenerQueue, block)
            }
        }
        for id in current.subtracting(registered) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.recompute() }
            }
            var addr = Self.audioRunningAddress
            if AudioObjectAddPropertyListenerBlock(id, &addr, listenerQueue, block) == noErr {
                audioDeviceListeners[id] = block
            }
        }
        recompute()
    }

    private func unregisterAudio() {
        for (id, block) in audioDeviceListeners {
            var addr = Self.audioRunningAddress
            AudioObjectRemovePropertyListenerBlock(id, &addr, listenerQueue, block)
        }
        audioDeviceListeners.removeAll()
        if let block = audioListListener {
            var addr = Self.audioDevicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue, block)
            audioListListener = nil
        }
    }

    // MARK: - CoreMediaIO

    private static var camDevicesAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    private static var camRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    private static func cameraDevices() -> [CMIOObjectID] {
        var addr = camDevicesAddress
        var size: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return ids
    }

    private static func camRunning(_ id: CMIOObjectID) -> Bool {
        var addr = camRunningAddress
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, &value) == 0 else { return false }
        return value != 0
    }

    private func registerCamera() -> Bool {
        // Inclui dispositivos DAL/tela na enumeração (não é necessário para webcams comuns).
        var allowAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &allowAddr, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size), &allow)

        let listBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.syncCameraDevices() }
        }
        var addr = Self.camDevicesAddress
        let status = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, listenerQueue, listBlock)
        guard status == 0 else { return false }
        camListListener = listBlock
        syncCameraDevices()
        return true
    }

    private func syncCameraDevices() {
        guard running else { return }
        let current = Set(Self.cameraDevices())
        let registered = Set(camDeviceListeners.keys)

        for id in registered.subtracting(current) {
            if let block = camDeviceListeners.removeValue(forKey: id) {
                var addr = Self.camRunningAddress
                CMIOObjectRemovePropertyListenerBlock(id, &addr, listenerQueue, block)
            }
        }
        var failed = false
        for id in current.subtracting(registered) {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.recompute() }
            }
            var addr = Self.camRunningAddress
            if CMIOObjectAddPropertyListenerBlock(id, &addr, listenerQueue, block) == 0 {
                camDeviceListeners[id] = block
            } else {
                failed = true
            }
        }
        if failed && pollTimer == nil { startPolling() }
        recompute()
    }

    private func unregisterCamera() {
        for (id, block) in camDeviceListeners {
            var addr = Self.camRunningAddress
            CMIOObjectRemovePropertyListenerBlock(id, &addr, listenerQueue, block)
        }
        camDeviceListeners.removeAll()
        if let block = camListListener {
            var addr = Self.camDevicesAddress
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, listenerQueue, block)
            camListListener = nil
        }
    }
}
