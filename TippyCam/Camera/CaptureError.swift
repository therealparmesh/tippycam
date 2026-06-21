import Foundation

enum CaptureError: LocalizedError, Sendable {
    case cameraUnavailable
    case configurationFailed
    case captureInProgress
    case captureFailed
    case invalidPhotoData
    case processingFailed
    case photoLibraryPermissionDenied
    case photoSaveFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "Camera is not available on this device."
        case .configurationFailed:
            "The camera could not be configured."
        case .captureInProgress:
            "A photo is already being captured."
        case .captureFailed:
            "The photo could not be captured."
        case .invalidPhotoData:
            "The captured photo data is invalid."
        case .processingFailed:
            "The photo could not be processed."
        case .photoLibraryPermissionDenied:
            "Photos access is required to save photos."
        case .photoSaveFailed:
            "The photo could not be saved to Photos."
        }
    }
}
