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
        guard let previewLayer = view.previewLayer else { return view }
        previewLayer.session = session
        previewLayer.backgroundColor = UIColor.black.cgColor
        previewLayer.contentsScale = view.traitCollection.displayScale
        previewLayer.videoGravity = .resizeAspectFill
        updateMirroring(for: previewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        guard let previewLayer = uiView.previewLayer else { return }
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        previewLayer.contentsScale = uiView.traitCollection.displayScale
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
            updateMirroring(for: connection)
        }
    }

    private func updateMirroring(for connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}

final class PreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }
}
