@preconcurrency import AVFoundation
import Foundation

final class CameraSessionManager: @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.parmscript.tippycam.camera-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var captureProcessor: PhotoCaptureProcessor?
    private var cameraInput: AVCaptureDeviceInput?
    private var cameraPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var supportsPortrait = false

    func configure() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    if !self.isConfigured {
                        try self.configureSession()
                    }
                    continuation.resume(returning: self.supportsPortrait)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startRunning() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.isConfigured, !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func switchCamera() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.isConfigured else {
                    continuation.resume(throwing: CaptureError.configurationFailed)
                    return
                }
                guard self.captureProcessor == nil else {
                    continuation.resume(throwing: CaptureError.captureInProgress)
                    return
                }

                let newPosition: AVCaptureDevice.Position = self.cameraPosition == .back
                    ? .front
                    : .back

                do {
                    try self.replaceCameraInput(with: newPosition)
                    continuation.resume(returning: self.supportsPortrait)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func capturePhoto(mode: CameraMode) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.isConfigured else {
                    continuation.resume(throwing: CaptureError.configurationFailed)
                    return
                }
                guard self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.captureFailed)
                    return
                }
                guard self.captureProcessor == nil else {
                    continuation.resume(throwing: CaptureError.captureInProgress)
                    return
                }

                let settings = self.makePhotoSettings(mode: mode)

                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = self.cameraPosition == .front
                    }
                }

                let processor = PhotoCaptureProcessor(
                    continuation: continuation,
                    didFinish: { [weak self] in
                        guard let self else { return }
                        self.sessionQueue.async {
                            self.captureProcessor = nil
                        }
                    }
                )
                self.captureProcessor = processor
                self.photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }

    private func configureSession() throws {
        guard let camera = DeviceCapabilities.camera(for: .back) else {
            throw CaptureError.cameraUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw CaptureError.configurationFailed
        }

        session.beginConfiguration()
        setBestPhotoSessionPreset()

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed
        }

        session.addInput(input)
        cameraInput = input
        cameraPosition = .back
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        configurePhotoCapabilities()
        configureCamera(camera)
        session.commitConfiguration()
        applyPreferredPhotoDimensions(for: camera)
        preparePhotoOutput()
        isConfigured = true
    }

    private func replaceCameraInput(with position: AVCaptureDevice.Position) throws {
        guard let camera = DeviceCapabilities.camera(for: position) else {
            throw CaptureError.cameraUnavailable
        }

        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw CaptureError.configurationFailed
        }

        session.beginConfiguration()

        let previousInput = cameraInput
        let previousPosition = cameraPosition

        if let previousInput {
            session.removeInput(previousInput)
        }

        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                cameraInput = previousInput
                cameraPosition = previousPosition
            } else {
                // Session has no camera input; mark as unconfigured
                cameraInput = nil
                isConfigured = false
            }
            session.commitConfiguration()
            throw CaptureError.configurationFailed
        }

        session.addInput(newInput)
        cameraInput = newInput
        cameraPosition = position

        configurePhotoCapabilities()
        configureCamera(camera)
        session.commitConfiguration()
        applyPreferredPhotoDimensions(for: camera)
        preparePhotoOutput()
    }
}

private extension CameraSessionManager {
    private func configurePhotoCapabilities() {
        if photoOutput.isContentAwareDistortionCorrectionSupported {
            photoOutput.isContentAwareDistortionCorrectionEnabled = true
        }

        supportsPortrait = photoOutput.isDepthDataDeliverySupported
        photoOutput.isDepthDataDeliveryEnabled = supportsPortrait
        photoOutput.isPortraitEffectsMatteDeliveryEnabled =
            supportsPortrait && photoOutput.isPortraitEffectsMatteDeliverySupported

        if photoOutput.isZeroShutterLagSupported {
            photoOutput.isZeroShutterLagEnabled = true
        }
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
        }
        if photoOutput.isCameraSensorOrientationCompensationSupported {
            photoOutput.isCameraSensorOrientationCompensationEnabled = true
        }
    }

    private func configureCamera(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isGeometricDistortionCorrectionSupported {
                camera.isGeometricDistortionCorrectionEnabled = true
            }
            camera.unlockForConfiguration()
        } catch {
            AppLog.camera.warning("Camera focus/exposure configuration failed: \(error.localizedDescription)")
        }
    }

    private func preferredPhotoDimensions(in format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions
            .filter(isFourByThree)
            .max { pixelCount($0) < pixelCount($1) }
            ?? format.supportedMaxPhotoDimensions.max { lhs, rhs in
                pixelCount(lhs) < pixelCount(rhs)
            }
    }

    private func setBestPhotoSessionPreset() {
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
    }

    private func applyPreferredPhotoDimensions(for camera: AVCaptureDevice) {
        guard let dimensions = preferredPhotoDimensions(in: camera.activeFormat) else {
            return
        }
        photoOutput.maxPhotoDimensions = dimensions
    }

    private func preparePhotoOutput() {
        var settings = [makePhotoSettings(mode: .photo)]
        if supportsPortrait {
            settings.append(makePhotoSettings(mode: .portrait))
        }

        photoOutput.setPreparedPhotoSettingsArray(settings) { _, error in
            if let error {
                AppLog.camera.warning("Photo preparation failed: \(error.localizedDescription)")
            }
        }
    }

    private func makePhotoSettings(mode: CameraMode) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        settings.isAutoVirtualDeviceFusionEnabled = true
        settings.isAutoRedEyeReductionEnabled = photoOutput.isAutoRedEyeReductionSupported
        settings.isAutoContentAwareDistortionCorrectionEnabled =
            photoOutput.isContentAwareDistortionCorrectionEnabled

        let wantsDepth = mode == .portrait && photoOutput.isDepthDataDeliveryEnabled
        settings.isDepthDataDeliveryEnabled = wantsDepth
        settings.embedsDepthDataInPhoto = wantsDepth
        settings.isDepthDataFiltered = true

        let wantsPortraitMatte = wantsDepth && photoOutput.isPortraitEffectsMatteDeliveryEnabled
        settings.isPortraitEffectsMatteDeliveryEnabled = wantsPortraitMatte
        settings.embedsPortraitEffectsMatteInPhoto = wantsPortraitMatte

        return settings
    }

    private func isFourByThree(_ dimensions: CMVideoDimensions) -> Bool {
        let shortSide = CGFloat(min(dimensions.width, dimensions.height))
        let longSide = CGFloat(max(dimensions.width, dimensions.height))
        guard shortSide > 0 else { return false }
        return abs((longSide / shortSide) - (4.0 / 3.0)) < 0.02
    }

    private func pixelCount(_ dimensions: CMVideoDimensions) -> Int64 {
        Int64(dimensions.width) * Int64(dimensions.height)
    }
}
