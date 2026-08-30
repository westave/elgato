// camera-state: печатает "on"/"off" в зависимости от того, использует ли
// какой-либо процесс камеру прямо сейчас (CoreMediaIO,
// kCMIODevicePropertyDeviceIsRunningSomewhere — тот же механизм, что и
// зелёный индикатор камеры в macOS).
//
// Сборка: swiftc -O Tools/camera-state.swift -o .build/camera-state
// Коды выхода: 0 = камера активна, 1 = неактивна, 2 = ошибка.

import CoreMediaIO
import Foundation

func cmioDevices() -> [CMIOObjectID] {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    var dataSize: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize
    ) == kCMIOHardwareNoError, dataSize > 0 else {
        return []
    }

    let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
    var devices = [CMIOObjectID](repeating: 0, count: count)
    var dataUsed: UInt32 = 0
    guard CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
        dataSize, &dataUsed, &devices
    ) == kCMIOHardwareNoError else {
        return []
    }

    return devices
}

func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
    )

    guard CMIOObjectHasProperty(device, &address) else { return false }

    var dataSize: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == kCMIOHardwareNoError,
          dataSize > 0 else {
        return false
    }

    var value: UInt32 = 0
    var dataUsed: UInt32 = 0
    guard CMIOObjectGetPropertyData(
        device, &address, 0, nil, dataSize, &dataUsed, &value
    ) == kCMIOHardwareNoError else {
        return false
    }

    return value != 0
}

let devices = cmioDevices()
guard !devices.isEmpty else {
    FileHandle.standardError.write("no camera devices found\n".data(using: .utf8)!)
    print("off")
    exit(1)
}

let active = devices.contains(where: isRunningSomewhere)
print(active ? "on" : "off")
exit(active ? 0 : 1)
