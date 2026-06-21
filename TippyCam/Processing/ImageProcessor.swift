@preconcurrency import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

struct ProcessedPhotoResult: @unchecked Sendable {
    let image: UIImage
    let data: Data
    let portraitDepthApplied: Bool
    let usedPortraitFallback: Bool
}

final class ImageProcessor: @unchecked Sendable {
    static let shared = ImageProcessor()
    static let portraitAperture: Float = 4

    private let context: CIContext
    private let colorSpace: CGColorSpace

    private init() {
        colorSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpaceCreateDeviceRGB()
        context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: colorSpace
        ])
    }

    func processedPhoto(from imageData: Data, mode: CameraMode) async throws -> ProcessedPhotoResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try autoreleasepool {
                try renderPhoto(from: imageData, mode: mode)
            }
        }.value
    }

    private func renderPhoto(from imageData: Data, mode: CameraMode) throws -> ProcessedPhotoResult {
        let depthImage = mode == .portrait
            ? try portraitCIImage(from: imageData)
            : nil

        guard let inputImage = depthImage ?? stillCIImage(from: imageData) else {
            throw CaptureError.invalidPhotoData
        }

        let normalizedInput = zeroBased(inputImage)
        let settings = TippyLookSettings(mode: mode)
        let renderedImage = applyTippyLook(to: normalizedInput, settings: settings)
            .cropped(to: normalizedInput.extent)
        guard let cgImage = context.createCGImage(renderedImage, from: renderedImage.extent) else {
            throw CaptureError.processingFailed
        }
        let data = try encodedPhotoData(from: renderedImage, compressionQuality: 0.98)

        return ProcessedPhotoResult(
            image: UIImage(cgImage: cgImage, scale: 1, orientation: .up),
            data: data,
            portraitDepthApplied: depthImage != nil,
            usedPortraitFallback: mode == .portrait && depthImage == nil
        )
    }

    private func stillCIImage(from imageData: Data) -> CIImage? {
        CIImage(
            data: imageData,
            options: [
                .applyOrientationProperty: true,
                .colorSpace: colorSpace,
                .expandToHDR: true,
                .toneMapHDRtoSDR: false
            ]
        )
    }

    private func portraitCIImage(from imageData: Data) throws -> CIImage? {
        guard let filter = context.depthBlurEffectFilter(forImageData: imageData, options: nil) else {
            return nil
        }

        filter.setValue(Self.portraitAperture, forKey: "inputAperture")
        guard let outputImage = filter.outputImage else {
            throw CaptureError.processingFailed
        }
        return ImageOrientationFixer.normalizedCIImage(outputImage, from: imageData)
    }

    private func applyTippyLook(to image: CIImage, settings: TippyLookSettings) -> CIImage {
        var output = image

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = output
        exposure.ev = settings.exposureEV
        output = exposure.outputImage ?? output

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = output
        highlightShadow.highlightAmount = settings.highlightAmount
        highlightShadow.shadowAmount = settings.shadowAmount
        output = highlightShadow.outputImage ?? output

        output = applyToneCurve(to: output, settings: settings)

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.contrast = settings.contrast
        colorControls.saturation = settings.saturation
        output = colorControls.outputImage ?? output

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = output
        vibrance.amount = settings.vibrance
        output = vibrance.outputImage ?? output

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = output
        temperature.neutral = CIVector(x: 6_500, y: 0)
        temperature.targetNeutral = CIVector(x: CGFloat(settings.targetTemperature), y: 0)
        output = temperature.outputImage ?? output

        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = output
        noiseReduction.noiseLevel = settings.noiseLevel
        noiseReduction.sharpness = settings.noiseSharpness
        output = noiseReduction.outputImage ?? output

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = output
        sharpen.sharpness = settings.sharpening
        output = sharpen.outputImage ?? output

        return output
    }

    private func encodedPhotoData(from image: CIImage, compressionQuality: CGFloat) throws -> Data {
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: compressionQuality,
            kCGImageDestinationEmbedThumbnail as CIImageRepresentationOption: true
        ]

        if let data = try? context.heif10Representation(
            of: image,
            colorSpace: colorSpace,
            options: options
        ) {
            return data
        }

        if let data = context.heifRepresentation(
            of: image,
            format: .RGBAh,
            colorSpace: colorSpace,
            options: options
        ) {
            return data
        }

        if let data = context.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: options
        ) {
            return data
        }

        throw CaptureError.processingFailed
    }

    private func applyToneCurve(to image: CIImage, settings: TippyLookSettings) -> CIImage {
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: settings.blackPoint)
        curve.point1 = CGPoint(x: 0.25, y: settings.shadowLift)
        curve.point2 = CGPoint(x: 0.50, y: settings.midLift)
        curve.point3 = CGPoint(x: 0.75, y: settings.highlightRollOff)
        curve.point4 = CGPoint(x: 1, y: settings.whitePoint)
        return curve.outputImage ?? image
    }

    private func zeroBased(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard extent.origin != .zero else {
            return image.cropped(to: extent)
        }
        return image
            .cropped(to: extent)
            .transformed(by: CGAffineTransform(
                translationX: -extent.origin.x,
                y: -extent.origin.y
            ))
    }
}

private struct TippyLookSettings {
    let exposureEV: Float
    let highlightAmount: Float
    let shadowAmount: Float
    let contrast: Float
    let saturation: Float
    let vibrance: Float
    let targetTemperature: Float
    let noiseLevel: Float
    let noiseSharpness: Float
    let sharpening: Float
    let blackPoint: CGFloat
    let shadowLift: CGFloat
    let midLift: CGFloat
    let highlightRollOff: CGFloat
    let whitePoint: CGFloat

    init(mode: CameraMode) {
        switch mode {
        case .photo:
            exposureEV = 0.10
            highlightAmount = 0.84
            shadowAmount = 0.32
            contrast = 1.06
            saturation = 1.045
            vibrance = 0.24
            targetTemperature = 6_100
            noiseLevel = 0.010
            noiseSharpness = 0.52
            sharpening = 0.18
            blackPoint = 0.006
            shadowLift = 0.292
            midLift = 0.535
            highlightRollOff = 0.820
            whitePoint = 0.996
        case .portrait:
            exposureEV = 0.08
            highlightAmount = 0.88
            shadowAmount = 0.24
            contrast = 1.025
            saturation = 1.025
            vibrance = 0.16
            targetTemperature = 6_000
            noiseLevel = 0.012
            noiseSharpness = 0.50
            sharpening = 0.06
            blackPoint = 0.008
            shadowLift = 0.278
            midLift = 0.526
            highlightRollOff = 0.835
            whitePoint = 0.996
        }
    }
}
