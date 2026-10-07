//
//  AudioOutputs.swift
//  MyOwnNotch
//
//  Reconhece as saídas de áudio do Mac (CoreAudio) e permite trocar a padrão.
//

import SwiftUI
import Combine
import CoreAudio

struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let icon: String
    var isDefault: Bool
}

@MainActor
final class AudioOutputs: ObservableObject {
    @Published private(set) var outputs: [AudioOutput] = []

    func refresh() { outputs = Self.list() }

    func select(_ output: AudioOutput) {
        var id = output.id
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        }
        refresh()
    }

    // MARK: CoreAudio

    private static func list() -> [AudioOutput] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var defaultID = AudioDeviceID(0)
        var dAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        var dSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &dAddr, 0, nil, &dSize, &defaultID)

        return ids.compactMap { id in
            guard outputChannels(id) > 0 else { return nil }
            let transport = transportType(id)
            if transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate { return nil }
            return AudioOutput(id: id, name: name(id), icon: icon(for: transport, name: name(id)), isDefault: id == defaultID)
        }
    }

    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfName) == noErr, let s = cfName?.takeRetainedValue() else { return "Dispositivo" }
        return s as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }

    private static func icon(for transport: UInt32, name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return lower.contains("headphone") || lower.contains("fones") ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        default: return "speaker.wave.2.fill"
        }
    }
}
