@preconcurrency import AVFoundation

struct CapturedPhoto: @unchecked Sendable {
    let data: Data
}

final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<CapturedPhoto, Error>
    private let didFinish: @Sendable () -> Void
    private var result: Result<CapturedPhoto, Error>?

    init(
        continuation: CheckedContinuation<CapturedPhoto, Error>,
        didFinish: @escaping @Sendable () -> Void
    ) {
        self.continuation = continuation
        self.didFinish = didFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            result = .failure(error)
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            result = .failure(CaptureError.invalidPhotoData)
            return
        }

        result = .success(CapturedPhoto(data: data))
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        defer { didFinish() }

        if let error {
            continuation.resume(throwing: error)
            return
        }

        switch result {
        case .success(let photo):
            continuation.resume(returning: photo)
        case .failure(let error):
            continuation.resume(throwing: error)
        case nil:
            continuation.resume(throwing: CaptureError.captureFailed)
        }
    }
}
