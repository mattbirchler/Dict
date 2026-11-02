import CoreAudio
import Foundation

/// CoreAudio lookups for the microphone Dict records from.
enum AudioInputDevices {
    /// The name of the system's default input device, for the HUD label.
    static var defaultInputDeviceName: String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )
        guard status == noErr else { return "Unknown Microphone" }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0, nil,
            &nameSize, &name
        )
        guard nameStatus == noErr else { return "Unknown Microphone" }
        return name as String
    }
}
