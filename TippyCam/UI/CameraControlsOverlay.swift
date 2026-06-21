import SwiftUI

struct CameraControlsOverlay: View {
    @Binding var mode: CameraMode

    let supportsPortrait: Bool
    let latestPhotoThumbnail: UIImage?
    let statusMessage: String?
    let isProcessing: Bool
    let isSwitchingCamera: Bool
    let isUsingFrontCamera: Bool
    let layout: CameraLayoutMetrics
    let openSettings: () -> Void
    let openGallery: () -> Void
    let switchCamera: () -> Void
    let capture: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraChromeBackground(layout: layout)

            topChrome
                .padding(.horizontal, 24)
                .padding(.top, layout.topChromeTop)

            bottomChrome
                .frame(width: layout.size.width, height: layout.bottomChromeHeight)
                .offset(y: layout.previewBottom)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .ignoresSafeArea()
    }

    private var topChrome: some View {
        HStack {
            Spacer()

            CameraMenuButton(
                isProcessing: isProcessing,
                openSettings: openSettings
            )
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            StatusBadge(message: statusMessage)
                .padding(.top, 10)
                .padding(.bottom, statusMessage == nil ? 0 : 8)

            HStack {
                Spacer()

                CaptureControlsView(
                    isProcessing: isProcessing,
                    capture: capture
                )
                .disabled(isSwitchingCamera)

                Spacer()
            }
            .frame(height: 90)
            .padding(.top, statusMessage == nil ? 14 : 0)

            Spacer(minLength: 10)

            HStack {
                PhotoLibraryButtonView(
                    image: latestPhotoThumbnail,
                    action: openGallery
                )
                .disabled(isProcessing)

                Spacer()

                CameraModePicker(
                    selection: $mode,
                    supportsPortrait: supportsPortrait
                )
                .disabled(isProcessing)

                Spacer()

                CameraFlipButton(
                    isSwitchingCamera: isSwitchingCamera,
                    isUsingFrontCamera: isUsingFrontCamera,
                    action: switchCamera
                )
                .disabled(isProcessing || isSwitchingCamera)
            }
            .frame(height: 58)
            .padding(.horizontal, 34)
            .padding(.bottom, layout.bottomSafePadding)
        }
    }
}

private struct CameraChromeBackground: View {
    let layout: CameraLayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: layout.previewTop)

            Color.clear
                .frame(height: layout.previewHeight)

            Color.black
                .frame(height: layout.bottomChromeHeight)
        }
    }
}

private struct CameraMenuButton: View {
    let isProcessing: Bool
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 60, height: 40)
                .background(.black.opacity(0.48), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(isProcessing)
        .accessibilityLabel("Camera menu")
    }
}

private struct StatusBadge: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.46), in: Capsule())
                .padding(.bottom, 4)
        }
    }
}

private struct CameraFlipButton: View {
    let isSwitchingCamera: Bool
    let isUsingFrontCamera: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSwitchingCamera {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.36), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isUsingFrontCamera
                ? "Switch to rear camera"
                : "Switch to front camera"
        )
    }
}
