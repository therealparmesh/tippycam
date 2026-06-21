@preconcurrency import AVFoundation

enum DeviceCapabilities {
    static var isSimulator: Bool {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }

    static func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        switch position {
        case .front:
            deviceTypes = [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera
            ]
        case .back:
            deviceTypes = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
        default:
            return nil
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        return discovery.devices.first
    }
}
