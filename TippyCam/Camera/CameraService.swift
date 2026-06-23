@preconcurrency import AVFoundation
import Observation

enum CameraViewState: Equatable {
    case idle
    case requestingPermission
    case configuring
    case ready
    case denied
    case unavailable(String)
}

@MainActor
@Observable
final class CameraService {
    var state: CameraViewState = .idle
    var isProcessing = false
    var statusMessage: String?
    var errorMessage: String?
    private(set) var isSwitchingCamera = false
    private(set) var isUsingFrontCamera = false
    private(set) var supportsPortrait = false
    private(set) var cameraMode: CameraMode = .photo

    let photoLibrary = PhotoLibraryService()

    @ObservationIgnored
    private lazy var sessionManager = CameraSessionManager()
    @ObservationIgnored
    private var statusTask: Task<Void, Never>?
    @ObservationIgnored
    private var shouldRunSession = false

    var session: AVCaptureSession? {
        state == .ready ? sessionManager.session : nil
    }

    func resume() async {
        shouldRunSession = true

        let currentAuth = AVCaptureDevice.authorizationStatus(for: .video)
        if state == .denied, currentAuth == .authorized {
            state = .idle
        } else if state == .ready, currentAuth != .authorized {
            sessionManager.stopRunning()
            state = .denied
        }

        switch state {
        case .idle:
            await prepare()
        case .ready:
            await sessionManager.startRunning()
        case .requestingPermission, .configuring, .denied, .unavailable:
            break
        }

        photoLibrary.refreshLatestThumbnail()
    }

    func pause() {
        shouldRunSession = false
        sessionManager.stopRunning()
    }

    private func prepare() async {
        guard state == .idle else { return }

        if DeviceCapabilities.isSimulator {
            state = .unavailable("Camera capture requires a real iPhone.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configureCamera()
        case .notDetermined:
            state = .requestingPermission
            if await AVCaptureDevice.requestAccess(for: .video) {
                await configureCamera()
            } else {
                state = .denied
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func capture() async {
        guard state == .ready, !isProcessing, !isSwitchingCamera else { return }

        errorMessage = nil
        let captureMode = cameraMode

        isProcessing = true
        setStatus("Capturing...")
        defer { isProcessing = false }

        do {
            let captured = try await sessionManager.capturePhoto(mode: captureMode)

            setStatus(captureMode == .portrait ? "Rendering Portrait..." : "Rendering...")
            let result = try await ImageProcessor.shared.processedPhoto(
                from: captured.data,
                mode: captureMode
            )

            setStatus("Saving...")
            try await photoLibrary.save(data: result.data)
            showTransientStatus(saveMessage(
                portraitRendered: result.portraitDepthApplied,
                portraitFallback: result.usedPortraitFallback
            ))
        } catch {
            AppLog.camera.error("Capture pipeline failed: \(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setStatus(nil)
        }
    }

    func switchCamera() async {
        guard state == .ready, !isProcessing, !isSwitchingCamera else { return }

        errorMessage = nil
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }

        do {
            supportsPortrait = try await sessionManager.switchCamera()
            isUsingFrontCamera.toggle()

            if cameraMode == .portrait, !supportsPortrait {
                selectMode(.photo)
                showTransientStatus("Portrait not available on this camera")
            }
        } catch {
            AppLog.camera.error("Camera switch failed: \(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectMode(_ mode: CameraMode) {
        guard mode != cameraMode else { return }

        switch mode {
        case .photo:
            cameraMode = .photo
        case .portrait:
            guard supportsPortrait else {
                showTransientStatus("Portrait not available on this iPhone")
                return
            }
            cameraMode = .portrait
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func configureCamera() async {
        state = .configuring
        do {
            supportsPortrait = try await sessionManager.configure()
            if shouldRunSession {
                await sessionManager.startRunning()
            }
            state = .ready
        } catch {
            AppLog.camera.error("Camera configuration failed: \(error.localizedDescription)")
            state = .unavailable(error.localizedDescription)
        }
    }

    private func setStatus(_ message: String?) {
        statusTask?.cancel()
        statusMessage = message
    }

    private func showTransientStatus(_ message: String) {
        setStatus(message)
        statusTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            guard statusMessage == message else { return }
            statusMessage = nil
        }
    }

    private func saveMessage(
        portraitRendered: Bool,
        portraitFallback: Bool
    ) -> String {
        if portraitRendered {
            return "Portrait saved"
        }
        if portraitFallback {
            return "Saved without Portrait effect"
        }
        return "Saved to Photos"
    }
}
