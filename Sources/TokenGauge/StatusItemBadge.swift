import AppKit

/// Renders the menu bar readout.
///
/// Drawn as an image rather than set as the button's title because the
/// provider labels are bold while their percentages are not, which a plain
/// title can't express. It's a template image, so the system tints it to match
/// the menu bar: white on a dark menu bar, black on a light one.
enum StatusItemBadge {
    /// One provider's readout: a short label and its remaining percentage.
    struct Segment: Equatable {
        let label: String
        let value: String
    }

    static func image(for segments: [Segment]) -> NSImage {
        let (text, separatorCenters) = layout(segments)
        let textSize = text.size()
        let width = ceil(textSize.width)
        let height = ceil(textSize.height)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            text.draw(at: .zero)

            // A triple-dash separator, stroked rather than typed: U+2506 isn't
            // in the system font, so typing it falls back to another face that
            // sits at a different size and baseline than the text beside it.
            //
            // Dash and gap are derived from the span so exactly three dashes
            // fill it: 3·dash + 2·gap == span when gap is half a dash.
            let bottom: CGFloat = 3
            let span = height - bottom * 2
            let dash = span / 4
            let gap = dash / 2

            let path = NSBezierPath()
            path.lineWidth = 1
            path.setLineDash([dash, gap], count: 2, phase: 0)
            for x in separatorCenters {
                let pixelAligned = floor(x) + 0.5
                path.move(to: NSPoint(x: pixelAligned, y: bottom))
                path.line(to: NSPoint(x: pixelAligned, y: bottom + span))
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Builds the readout and, alongside it, the x position of each gap left
    /// for a separator.
    private static func layout(_ segments: [Segment]) -> (NSAttributedString, [CGFloat]) {
        // Match the size the menu bar uses for everything else, but with
        // monospaced digits so the readout doesn't twitch wider and narrower
        // as the percentages tick over.
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor.black,
        ]

        let result = NSMutableAttributedString()
        var separatorCenters: [CGFloat] = []

        for segment in segments {
            if result.length > 0 {
                let start = result.size().width
                result.append(NSAttributedString(string: "   ", attributes: valueAttributes))
                separatorCenters.append((start + result.size().width) / 2)
            }
            result.append(NSAttributedString(string: segment.label, attributes: labelAttributes))
            result.append(NSAttributedString(string: " " + segment.value, attributes: valueAttributes))
        }
        return (result, separatorCenters)
    }
}
