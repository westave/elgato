import CoreMediaIO
import Foundation

/// Определение активности камеры через CoreMediaIO
/// (kCMIODevicePropertyDeviceIsRunningSomewhere — тот же сигнал, что и
/// зелёный индикатор macOS). Работает на Intel и Apple Silicon.
enum CameraMonitor {

    static func isCameraActive() -> Bool {
        devices().contains(where: isRunningSomewhere)
    }

    private static func devices() -> [CMIOObjectID] {
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
        var result = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
            dataSize, &dataUsed, &result
        ) == kCMIOHardwareNoError else {
            return []
        }

        return result
    }

    private static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
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
}
