import Foundation
import AVFoundation
import CoreMediaIO

class CameraMonitor {
    private var timer: Timer?
    private var lastCameraState = false
    private let statusChangeCallback: (Bool) -> Void
    private let checkInterval: TimeInterval = 2.0

    init(statusChangeCallback: @escaping (Bool) -> Void) {
        self.statusChangeCallback = statusChangeCallback
        enableCameraExtensions()
    }

    private func enableCameraExtensions() {
        // Enable camera extensions for better detection
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var allow: UInt32 = 1
        let sizeOfAllow = MemoryLayout<UInt32>.size

        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &property,
            0,
            nil,
            UInt32(sizeOfAllow),
            &allow
        )
    }

    func startMonitoring() {
        print("Starting camera monitoring...")

        // Check permissions
        checkCameraPermissions()

        // Start periodic monitoring
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkCameraStatus()
        }

        // Initial check
        checkCameraStatus()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("Camera access authorized")
        case .notDetermined:
            print("Camera access not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("Camera access \(granted ? "granted" : "denied")")
            }
        case .denied, .restricted:
            print("Camera access denied/restricted")
        @unknown default:
            print("Unknown camera authorization status")
        }
    }

    private func checkCameraStatus() {
        let isActive = isCameraInUse()

        if isActive != lastCameraState {
            print("Camera state changed: \(isActive)")
            lastCameraState = isActive
            statusChangeCallback(isActive)
        }
    }

    private func isCameraInUse() -> Bool {
        // Method 1: Check via AVCaptureDevice
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices

        for device in devices {
            if device.isConnected && !device.isSuspended {
                // Check if device is in use by checking if we can open it exclusively
                let captureSession = AVCaptureSession()
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if captureSession.canAddInput(input) {
                        // Device is available (not in use)
                        continue
                    } else {
                        // Device might be in use
                        return true
                    }
                } catch {
                    // If we can't create input, device is likely in use
                    return true
                }
            }
        }

        // Method 2: Check using lsof command (more reliable)
        return checkCameraViaProcess()
    }

    private func checkCameraViaProcess() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-w"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Look for camera-related devices
                let cameraKeywords = [
                    "AppleCamera",
                    "VDCAssistant",
                    "FaceTime",
                    "Camera",
                    "USBVDC",
                    "0x8000000004",  // FaceTime HD Camera (Built-in)
                ]

                for keyword in cameraKeywords {
                    if output.contains(keyword) {
                        return true
                    }
                }
            }
        } catch {
            print("Error running lsof: \(error)")
        }

        return false
    }

    deinit {
        stopMonitoring()
    }
}
