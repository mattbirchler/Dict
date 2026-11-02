import Foundation

/// Which microphone to record from. Stored as JSON in Settings.
enum InputDeviceChoice: Equatable, Hashable, Codable {
    /// The system default, except that a Bluetooth headset gives way to the
    /// built-in mic: headsets record at phone quality and take over output.
    case automatic
    /// Whatever macOS routes input to, Bluetooth included.
    case systemDefault
    /// One specific device by its stable UID.
    case device(uid: String)

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .systemDefault: "System default"
        case .device: "Chosen microphone"
        }
    }
}

enum InputDeviceSelection {
    /// The device a choice resolves to given what's connected right now.
    /// A chosen device that's unplugged falls back to Automatic rather than
    /// failing to record.
    static func resolve(
        _ choice: InputDeviceChoice,
        devices: [AudioInputDevice],
        systemDefault: AudioInputDevice?
    ) -> AudioInputDevice? {
        switch choice {
        case .systemDefault:
            return systemDefault
        case .device(let uid):
            if let match = devices.first(where: { $0.uid == uid }) { return match }
            return resolve(.automatic, devices: devices, systemDefault: systemDefault)
        case .automatic:
            guard let systemDefault else { return devices.first }
            if systemDefault.transport == .bluetooth,
               let builtIn = devices.first(where: { $0.transport == .builtIn }) {
                return builtIn
            }
            return systemDefault
        }
    }
}
