import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

/// A microphone CoreAudio knows about.
struct AudioInputDevice: Identifiable, Equatable {
    enum Transport: Equatable {
        case builtIn, bluetooth, usb, other
    }

    let id: AudioDeviceID
    /// Stable across reboots and reconnects, unlike `id`.
    let uid: String
    let name: String
    let transport: Transport
}

enum AudioInputError: Error {
    case noInputUnit
    case setDeviceFailed(OSStatus)
}

/// CoreAudio lookups for the microphones Dict can record from.
nonisolated enum AudioInputDevices {
    /// Every device with at least one input stream.
    static func all() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device(for:))
    }

    /// The device macOS currently routes input to.
    static func systemDefault() -> AudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return device(for: deviceID)
    }

    /// Points `engine`'s input node at `id`. Must run while the engine is
    /// stopped and before anything reads the input node's format.
    static func apply(_ id: AudioDeviceID, to engine: AVAudioEngine) throws {
        // withAudioUnit arrived with the macOS 27 SDK (Xcode 27, Swift 6.4).
        // Older toolchains, including the ones on GitHub's runners, build
        // the deprecated-but-working path instead.
        #if swift(>=6.4)
        if #available(macOS 27.0, *) {
            try engine.inputNode.withAudioUnit { unit in
                guard let unit else { throw AudioInputError.noInputUnit }
                try setCurrentDevice(id, on: unit)
            }
            return
        }
        #endif
        guard let unit = engine.inputNode.audioUnit else { throw AudioInputError.noInputUnit }
        try setCurrentDevice(id, on: unit)
    }

    private static func setCurrentDevice(_ id: AudioDeviceID, on unit: AudioUnit) throws {
        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioInputError.setDeviceFailed(status) }
    }

    /// `apply`, but a failure only costs the choice of microphone: the
    /// engine records from its current device and the failure is logged.
    static func applyIfPossible(_ id: AudioDeviceID?, to engine: AVAudioEngine) {
        guard let id else { return }
        do {
            try apply(id, to: engine)
        } catch {
            Log.engine.error("Couldn't select input device \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Property helpers

    private static func device(for id: AudioDeviceID) -> AudioInputDevice? {
        guard inputStreamCount(id) > 0,
              let uid = string(kAudioDevicePropertyDeviceUID, of: id),
              let name = string(kAudioDevicePropertyDeviceNameCFString, of: id) else { return nil }
        return AudioInputDevice(id: id, uid: uid, name: name, transport: transport(of: id))
    }

    private static func inputStreamCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func transport(of id: AudioDeviceID) -> AudioInputDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return .other }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        default: return .other
        }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
