import CoreImage
import ImageIO

enum ImageOrientationFixer {
    static func normalizedCIImage(_ image: CIImage, from data: Data) -> CIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = cgImageOrientation(from: properties) else {
            return image
        }

        guard shouldApplyOrientation(
            orientation,
            outputSize: image.extent.size,
            properties: properties
        ) else {
            return image
        }

        return image.oriented(forExifOrientation: Int32(orientation.rawValue))
    }

    private static func cgImageOrientation(
        from properties: [CFString: Any]
    ) -> CGImagePropertyOrientation? {
        guard let rawValue = orientationRawValue(from: properties[kCGImagePropertyOrientation]) else {
            return nil
        }
        return CGImagePropertyOrientation(rawValue: rawValue)
    }

    private static func shouldApplyOrientation(
        _ orientation: CGImagePropertyOrientation,
        outputSize: CGSize,
        properties: [CFString: Any]
    ) -> Bool {
        guard orientation != .up else { return false }
        guard orientation.swapsWidthAndHeight else { return true }
        guard let sourceSize = pixelSize(from: properties) else { return true }

        let displaySize = CGSize(width: sourceSize.height, height: sourceSize.width)
        if outputSize.isApproximatelyEqual(to: displaySize) {
            return false
        }
        if outputSize.isApproximatelyEqual(to: sourceSize) {
            return true
        }

        return outputSize.width > outputSize.height
    }

    private static func pixelSize(from properties: [CFString: Any]) -> CGSize? {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func orientationRawValue(from value: Any?) -> UInt32? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        return value as? UInt32
    }
}

private extension CGImagePropertyOrientation {
    var swapsWidthAndHeight: Bool {
        switch self {
        case .left, .right, .leftMirrored, .rightMirrored:
            true
        case .up, .down, .upMirrored, .downMirrored:
            false
        }
    }
}

private extension CGSize {
    func isApproximatelyEqual(to other: CGSize) -> Bool {
        abs(width - other.width) <= 2 && abs(height - other.height) <= 2
    }
}
