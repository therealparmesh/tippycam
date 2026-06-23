@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.isOpaque = true
        view.isMirrored = isMirrored
        guard let previewLayer = view.previewLayer else { return view }
        previewLayer.session = session
        previewLayer.backgroundColor = UIColor.black.cgColor
        previewLayer.contentsScale = view.traitCollection.displayScale
        previewLayer.videoGravity = .resizeAspectFill
        applyConnectionSettings(previewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        let mirrorChanged = uiView.isMirrored != isMirrored
        uiView.isMirrored = isMirrored
        guard let previewLayer = uiView.previewLayer else { return }
        if previewLayer.session !== session {
            previewLayer.session = session
            uiView.setNeedsConnectionUpdate()
        }
        previewLayer.contentsScale = uiView.traitCollection.displayScale
        if mirrorChanged {
            uiView.setNeedsConnectionUpdate()
        }
        applyConnectionSettings(previewLayer.connection)
    }

    private func applyConnectionSettings(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}

final class PreviewView: UIView {
    var isMirrored = false
    private var didApplyConnection = false

    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    func setNeedsConnectionUpdate() {
        didApplyConnection = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didApplyConnection else { return }
        guard let connection = previewLayer?.connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
        didApplyConnection = true
    }
}
