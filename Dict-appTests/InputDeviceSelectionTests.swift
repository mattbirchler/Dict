import Testing
@testable import Dict_app

struct InputDeviceSelectionTests {
    let builtIn = AudioInputDevice(id: 1, uid: "built", name: "MacBook Pro Microphone", transport: .builtIn)
    let airpods = AudioInputDevice(id: 2, uid: "air", name: "AirPods Pro", transport: .bluetooth)
    let usb = AudioInputDevice(id: 3, uid: "usb", name: "Yeti", transport: .usb)

    @Test func automaticSkipsBluetoothDefault() {
        #expect(InputDeviceSelection.resolve(.automatic, devices: [builtIn, airpods], systemDefault: airpods) == builtIn)
    }

    @Test func automaticKeepsUSBDefault() {
        #expect(InputDeviceSelection.resolve(.automatic, devices: [builtIn, usb], systemDefault: usb) == usb)
    }

    @Test func automaticKeepsBluetoothWhenNothingBuiltIn() {
        #expect(InputDeviceSelection.resolve(.automatic, devices: [airpods, usb], systemDefault: airpods) == airpods)
    }

    @Test func unpluggedSavedDeviceFallsBackToAutomatic() {
        #expect(InputDeviceSelection.resolve(.device(uid: "usb"), devices: [builtIn, airpods], systemDefault: airpods) == builtIn)
    }

    @Test func savedDeviceIsUsedWhenPresent() {
        #expect(InputDeviceSelection.resolve(.device(uid: "usb"), devices: [builtIn, usb], systemDefault: builtIn) == usb)
    }

    @Test func systemDefaultIsHonoredEvenWhenBluetooth() {
        #expect(InputDeviceSelection.resolve(.systemDefault, devices: [builtIn, airpods], systemDefault: airpods) == airpods)
    }

    @Test func noDevicesGivesNil() {
        #expect(InputDeviceSelection.resolve(.automatic, devices: [], systemDefault: nil) == nil)
    }

    @Test func displayNames() {
        #expect(InputDeviceChoice.automatic.displayName == "Automatic")
        #expect(InputDeviceChoice.systemDefault.displayName == "System default")
    }
}
