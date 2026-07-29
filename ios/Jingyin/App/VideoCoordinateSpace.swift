import CoreGraphics

enum VideoCoordinateSpace {
    /// Returns the display-oriented size after applying the asset track's
    /// preferred transform. Translation is intentionally included by
    /// transforming a rectangle, then standardizing its bounds.
    static func displaySize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return .zero }
        let transformed = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        return CGSize(width: transformed.width, height: transformed.height)
    }

    static func aspectFitBounds(
        displaySize: CGSize?,
        in containerSize: CGSize
    ) -> CGRect {
        guard let displaySize,
              displaySize.width > 0,
              displaySize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(
            containerSize.width / displaySize.width,
            containerSize.height / displaySize.height
        )
        let fittedSize = CGSize(
            width: displaySize.width * scale,
            height: displaySize.height * scale
        )
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

#if DEBUG
enum VideoCoordinateSpaceSmoke {
    static func run() {
        let landscape = CGSize(width: 1920, height: 1080)
        assertSize(
            VideoCoordinateSpace.displaySize(
                naturalSize: landscape,
                preferredTransform: .identity
            ),
            equals: landscape
        )
        assertSize(
            VideoCoordinateSpace.displaySize(
                naturalSize: landscape,
                preferredTransform: CGAffineTransform(
                    a: 0,
                    b: 1,
                    c: -1,
                    d: 0,
                    tx: 1080,
                    ty: 0
                )
            ),
            equals: CGSize(width: 1080, height: 1920)
        )
        assertSize(
            VideoCoordinateSpace.displaySize(
                naturalSize: landscape,
                preferredTransform: CGAffineTransform(
                    a: 0,
                    b: -1,
                    c: 1,
                    d: 0,
                    tx: 0,
                    ty: 1920
                )
            ),
            equals: CGSize(width: 1080, height: 1920)
        )
        assertSize(
            VideoCoordinateSpace.displaySize(
                naturalSize: landscape,
                preferredTransform: CGAffineTransform(
                    a: -1,
                    b: 0,
                    c: 0,
                    d: -1,
                    tx: 1920,
                    ty: 1080
                )
            ),
            equals: landscape
        )

        let normalized = NormalizedVideoRect(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.25
        )
        precondition(
            approximatelyEqual(
                NormalizedVideoRect(
                    visionBoundingBox: normalized.visionBoundingBox
                ).cgRect,
                normalized.cgRect
            ),
            "Vision/display normalized coordinate round trip failed"
        )
        precondition(
            approximatelyEqual(
                normalized.rect(
                    inCoreImageExtent: CGRect(
                        x: 0,
                        y: 0,
                        width: 2000,
                        height: 1000
                    )
                ),
                CGRect(x: 200, y: 550, width: 600, height: 250)
            ),
            "Display/Core Image coordinate conversion failed"
        )
        precondition(
            approximatelyEqual(
                VideoCoordinateSpace.aspectFitBounds(
                    displaySize: CGSize(width: 1080, height: 1920),
                    in: CGSize(width: 390, height: 240)
                ),
                CGRect(x: 127.5, y: 0, width: 135, height: 240)
            ),
            "Portrait aspect-fit bounds failed"
        )
        precondition(
            approximatelyEqual(
                VideoCoordinateSpace.aspectFitBounds(
                    displaySize: landscape,
                    in: CGSize(width: 390, height: 240)
                ),
                CGRect(x: 0, y: 10.3125, width: 390, height: 219.375)
            ),
            "Landscape aspect-fit bounds failed"
        )
    }

    private static func assertSize(_ lhs: CGSize, equals rhs: CGSize) {
        precondition(
            abs(lhs.width - rhs.width) < 0.001
                && abs(lhs.height - rhs.height) < 0.001,
            "Unexpected display size: \(lhs), expected \(rhs)"
        )
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.001
            && abs(lhs.minY - rhs.minY) < 0.001
            && abs(lhs.width - rhs.width) < 0.001
            && abs(lhs.height - rhs.height) < 0.001
    }
}
#endif
