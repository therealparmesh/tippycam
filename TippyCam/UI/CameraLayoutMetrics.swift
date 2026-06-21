import SwiftUI

struct CameraLayoutMetrics {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var previewTop: CGFloat {
        let availableTop = size.height - naturalPreviewHeight - minimumBottomChromeHeight
        return max(minimumPreviewTop, min(preferredPreviewTop, availableTop))
    }

    var previewHeight: CGFloat {
        let availableHeight = size.height - previewTop - minimumBottomChromeHeight
        return max(1, min(naturalPreviewHeight, availableHeight))
    }

    var previewBottom: CGFloat {
        previewTop + previewHeight
    }

    var previewMidY: CGFloat {
        previewTop + previewHeight / 2
    }

    var bottomChromeHeight: CGFloat {
        max(size.height - previewBottom, minimumBottomChromeHeight)
    }

    var bottomSafePadding: CGFloat {
        max(safeAreaInsets.bottom, 18)
    }

    var topChromeTop: CGFloat {
        max(safeAreaInsets.top + 18, previewTop - 68)
    }

    private var minimumPreviewTop: CGFloat {
        safeAreaInsets.top + 56
    }

    private var preferredPreviewTop: CGFloat {
        safeAreaInsets.top + 68
    }

    private var minimumBottomChromeHeight: CGFloat {
        safeAreaInsets.bottom + 176
    }

    private var naturalPreviewHeight: CGFloat {
        size.width / (3.0 / 4.0)
    }
}
