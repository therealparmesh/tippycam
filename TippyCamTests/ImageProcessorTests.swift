import UIKit
import XCTest
@testable import TippyCam

final class ImageProcessorTests: XCTestCase {
    func testTippyLookBrightensPhotoAndKeepsFullSize() async throws {
        let source = makeTopBottomImage()
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 0.95))
        let result = try await ImageProcessor.shared.processedPhoto(
            from: sourceData,
            mode: .photo
        )

        let resultImage = try XCTUnwrap(UIImage(data: result.data))
        XCTAssertEqual(resultImage.cgImage?.width, source.cgImage?.width)
        XCTAssertEqual(resultImage.cgImage?.height, source.cgImage?.height)
        XCTAssertGreaterThan(
            luminance(averageColor(of: resultImage)),
            luminance(averageColor(of: source)) + 0.02
        )
        XCTAssertGreaterThan(
            chroma(averageColor(of: resultImage)),
            chroma(averageColor(of: source)) + 0.01
        )
        XCTAssertFalse(result.portraitDepthApplied)
        XCTAssertFalse(result.usedPortraitFallback)
    }

    func testPortraitFallbackWithoutDepthKeepsFullSize() async throws {
        let source = makeTopBottomImage()
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 0.95))
        let result = try await ImageProcessor.shared.processedPhoto(
            from: sourceData,
            mode: .portrait
        )

        let resultImage = try XCTUnwrap(UIImage(data: result.data))
        XCTAssertEqual(resultImage.cgImage?.width, source.cgImage?.width)
        XCTAssertEqual(resultImage.cgImage?.height, source.cgImage?.height)
        XCTAssertFalse(result.portraitDepthApplied)
        XCTAssertTrue(result.usedPortraitFallback)
    }

    func testProcessedPhotoDataHappyPathEncodes() async throws {
        let source = makeTopBottomImage()
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 0.95))
        let result = try await ImageProcessor.shared.processedPhoto(
            from: sourceData,
            mode: .photo
        )
        let decoded = try XCTUnwrap(UIImage(data: result.data))

        XCTAssertEqual(decoded.cgImage?.width, source.cgImage?.width)
        XCTAssertEqual(decoded.cgImage?.height, source.cgImage?.height)
    }
}

private extension ImageProcessorTests {
    func makeTopBottomImage() -> UIImage {
        image(size: CGSize(width: 80, height: 120)) { context, rect in
            UIColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height / 2))
            UIColor(red: 0.18, green: 0.26, blue: 0.42, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: rect.height / 2, width: rect.width, height: rect.height / 2))
        }
    }

    func image(
        size: CGSize,
        draw: (CGContext, CGRect) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            draw(
                context.cgContext,
                CGRect(origin: .zero, size: size)
            )
        }
    }

    func averageColor(of image: UIImage) -> PixelColor {
        averageColor(of: image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func averageColor(of image: UIImage, in unitRect: CGRect) -> PixelColor {
        guard let cgImage = image.cgImage else {
            XCTFail("Expected CGImage-backed UIImage")
            return .black
        }
        let crop = CGRect(
            x: unitRect.minX * CGFloat(cgImage.width),
            y: unitRect.minY * CGFloat(cgImage.height),
            width: unitRect.width * CGFloat(cgImage.width),
            height: unitRect.height * CGFloat(cgImage.height)
        )
        guard let croppedImage = cgImage.cropping(to: crop.integral) else {
            XCTFail("Expected image crop")
            return .black
        }

        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return PixelColor(
            red: CGFloat(bytes[0]) / 255,
            green: CGFloat(bytes[1]) / 255,
            blue: CGFloat(bytes[2]) / 255
        )
    }

    func luminance(_ color: PixelColor) -> CGFloat {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }

    func chroma(_ color: PixelColor) -> CGFloat {
        max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue)
    }
}

private struct PixelColor {
    let red, green, blue: CGFloat

    static let black = PixelColor(red: 0, green: 0, blue: 0)
}
