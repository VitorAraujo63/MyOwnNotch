//
//  SystemAudioVolume.swift
//  MyOwnNotch
//
//  Volume e mute do dispositivo de saída padrão via CoreAudio, orientado a eventos
//  (sem polling). Re-registra os listeners quando o dispositivo padrão muda.
//

import Foundation
import CoreAudio
import AudioToolbox

final class SystemAudioVolume {

    struct Reading: Equatable {
        var volume: Double   // 0–1
        var muted: Bool
    }

    /// Chamado na main queue sempre que volume/mute mudam (não na leitura inicial).
    var onChange: ((Reading) -> Void)?

    private let queue = DispatchQueue.main
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var propertyBlock: AudioObjectPropertyListenerBlock?
    private var observedAddresses: [AudioObjectPropertyAddress] = []
    private var started = false

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: - Ciclo de vida

    func start() {
        guard !started else { return }
        started = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachToDefaultDevice()
            if let r = self?.read() { self?.onChange?(r) }
        }
        deviceBlock = block
        var addr = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        attachToDefaultDevice()
    }

    func stop() {
        guard started else { return }
        started = false
        detachFromDevice()
        if let block = deviceBlock {
            var addr = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        }
        deviceBlock = nil
    }

    deinit { /* stop() deve ser chamado explicitamente; blocos usam weak self */ }

    // MARK: - Leitura

    func read() -> Reading? {
        let id = Self.defaultOutputDevice()
        guard id != kAudioObjectUnknown else { return nil }
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = Self.volumeAddress
        guard AudioObjectHasProperty(id, &addr),
              AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        var muteVal = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var maddr = Self.muteAddress
        if AudioObjectHasProperty(id, &maddr) {
            AudioObjectGetPropertyData(id, &maddr, 0, nil, &msize, &muteVal)
        }
        return Reading(volume: Double(min(1, max(0, vol))), muted: muteVal != 0)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = defaultDeviceAddress
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    // MARK: - Listeners do dispositivo

    private func attachToDefaultDevice() {
        detachFromDevice()
        let id = Self.defaultOutputDevice()
        guard id != kAudioObjectUnknown else { return }
        deviceID = id
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            if let r = self?.read() { self?.onChange?(r) }
        }
        propertyBlock = block
        for var addr in [Self.volumeAddress, Self.muteAddress] where AudioObjectHasProperty(id, &addr) {
            if AudioObjectAddPropertyListenerBlock(id, &addr, queue, block) == noErr {
                observedAddresses.append(addr)
            }
        }
    }

    private func detachFromDevice() {
        if deviceID != kAudioObjectUnknown, let block = propertyBlock {
            for var addr in observedAddresses {
                AudioObjectRemovePropertyListenerBlock(deviceID, &addr, queue, block)
            }
        }
        observedAddresses = []
        propertyBlock = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }
}
