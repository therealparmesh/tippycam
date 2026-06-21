import AVFoundation
import AVKit
import SwiftUI

struct CameraScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraService()
    @State private var presentedSheet: CameraSheet?

    private var isCameraInteractive: Bool {
        presentedSheet == nil
            && camera.state == .ready
            && !camera.isProcessing
            && !camera.isSwitchingCamera
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = CameraLayoutMetrics(
                size: fullScreenSize(
                    containing: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets
                ),
                safeAreaInsets: proxy.safeAreaInsets
            )

            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraStateContent(
                    state: camera.state,
                    session: camera.session,
                    isPreviewMirrored: camera.isUsingFrontCamera,
                    layout: layout
                )

                if camera.state == .ready {
                    CameraControlsOverlay(
                        mode: modeBinding,
                        supportsPortrait: camera.supportsPortrait,
                        latestPhotoThumbnail: camera.photoLibrary.latestThumbnail,
                        statusMessage: camera.statusMessage,
                        isProcessing: camera.isProcessing,
                        isSwitchingCamera: camera.isSwitchingCamera,
                        isUsingFrontCamera: camera.isUsingFrontCamera,
                        layout: layout,
                        openSettings: openSettings,
                        openGallery: openGallery,
                        switchCamera: switchCamera,
                        capture: capture
                    )
                }
            }
            .ignoresSafeArea()
        }
        .onCameraCaptureEvent(
            isEnabled: isCameraInteractive,
            defaultSoundDisabled: false
        ) { event in
            if event.phase == .ended {
                capture()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await camera.resume()
        }
        .onChange(of: scenePhase) { _, newPhase in
            scenePhaseChanged(newPhase)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(modeSwipeGesture)
        .sheet(item: $presentedSheet, onDismiss: sheetDismissed) { sheet in
            switch sheet {
            case .settings:
                CameraSettingsView()
            case .gallery:
                PhotoGalleryView(library: camera.photoLibrary)
            }
        }
        .alert("Camera Issue", isPresented: errorBinding) {
            Button("OK") {
                camera.clearError()
            }
        } message: {
            Text(camera.errorMessage ?? "Something went wrong.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { camera.errorMessage != nil },
            set: { isPresented in
                if !isPresented { camera.clearError() }
            }
        )
    }

    private var modeBinding: Binding<CameraMode> {
        Binding(
            get: { camera.cameraMode },
            set: { mode in camera.selectMode(mode) }
        )
    }

    private func fullScreenSize(
        containing proxySize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGSize {
        let nativePreviewHeight = proxySize.width / (3.0 / 4.0)
        let minimumNativeCameraHeight = safeAreaInsets.top
            + 56
            + nativePreviewHeight
            + safeAreaInsets.bottom
            + 176
        guard proxySize.height < minimumNativeCameraHeight else {
            return proxySize
        }

        let expandedSize = CGSize(
            width: proxySize.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: proxySize.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return expandedSize.height >= minimumNativeCameraHeight ? expandedSize : proxySize
    }

    private func scenePhaseChanged(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            switch presentedSheet {
            case nil:
                Task { await camera.resume() }
            case .gallery:
                camera.photoLibrary.refresh()
            case .settings:
                camera.photoLibrary.refreshLatestThumbnail()
            }
        case .inactive, .background:
            camera.pause()
        @unknown default:
            break
        }
    }

    private func openSettings() {
        present(.settings)
    }

    private func openGallery() {
        present(.gallery)
    }

    private func capture() {
        guard isCameraInteractive else { return }
        Task { await camera.capture() }
    }

    private func switchCamera() {
        guard isCameraInteractive else { return }
        Task { await camera.switchCamera() }
    }

    private var modeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                handleModeSwipe(value.translation)
            }
    }

    private func handleModeSwipe(_ translation: CGSize) {
        guard isCameraInteractive else { return }
        guard abs(translation.width) > abs(translation.height),
              abs(translation.width) > 44 else {
            return
        }

        camera.selectMode(translation.width < 0 ? .portrait : .photo)
    }

    private func present(_ sheet: CameraSheet) {
        guard presentedSheet == nil, !camera.isProcessing else { return }
        camera.pause()
        presentedSheet = sheet
    }

    private func sheetDismissed() {
        guard scenePhase == .active else { return }
        Task { await camera.resume() }
    }
}

private enum CameraSheet: Identifiable {
    case settings
    case gallery

    var id: Self { self }
}

private struct CameraStateContent: View {
    let state: CameraViewState
    let session: AVCaptureSession?
    let isPreviewMirrored: Bool
    let layout: CameraLayoutMetrics

    var body: some View {
        Group {
            switch state {
            case .idle, .requestingPermission, .configuring:
                ProgressView(progressTitle)
                    .tint(.white)
                    .foregroundStyle(.white)
            case .ready:
                if let session {
                    CameraPreviewView(
                        session: session,
                        isMirrored: isPreviewMirrored
                    )
                    .frame(width: layout.size.width, height: layout.previewHeight)
                    .clipped()
                    .position(x: layout.size.width / 2, y: layout.previewMidY)
                } else {
                    ProgressView("Starting Camera...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            case .denied:
                PermissionDeniedView(
                    title: "Camera Access Required",
                    message: "Allow camera access in Settings to take photos."
                )
            case .unavailable(let message):
                PermissionDeniedView(
                    title: "Camera Unavailable",
                    message: message,
                    showsSettingsButton: false
                )
            }
        }
    }

    private var progressTitle: String {
        state == .requestingPermission ? "Requesting Camera Access..." : "Starting Camera..."
    }
}

#Preview {
    CameraScreen()
}
