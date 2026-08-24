import AppKit
import TokenGaugeCore

/// Renders the menu bar readout.
///
/// Drawn as an image rather than set as the button's title because it mixes
/// weights and colors that a plain title can't express.
///
/// This is *not* a template image: templates get flattened to one system tint,
/// which would throw away the provider accent and the usage colors. The cost
/// is that light/dark adaptation has to be done by hand, which is why the
/// caller passes `isDarkMenuBar` and re-renders when the appearance changes.
enum StatusItemBadge {
    /// One provider's readout. Carries the provider and the raw remaining
    /// percentage, not colors, so the styling lives here in one place.
    struct Segment: Equatable {
        let label: String
        let value: String
        let provider: Provider?
        let remaining: Double?
    }

    static func image(for segments: [Segment], isDarkMenuBar: Bool) -> NSImage {
        let (text, separatorCenters) = layout(segments, isDarkMenuBar: isDarkMenuBar)
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
            neutralColor(isDarkMenuBar).withAlphaComponent(0.5).setStroke()
            path.stroke()
            return true
        }
        return image
    }

    /// The plain foreground, matching what an untinted menu bar item would use.
    private static func neutralColor(_ isDarkMenuBar: Bool) -> NSColor {
        isDarkMenuBar ? .white : .black
    }

    /// Shares the panel's palette so the same percentage reads the same color
    /// in both places. "Plenty" follows the menu bar rather than being white
    /// outright, since white would vanish on a light menu bar.
    private static func usageColor(remaining: Double?, isDarkMenuBar: Bool) -> NSColor {
        UsagePalette.nsColor(remaining: remaining, plenty: neutralColor(isDarkMenuBar))
    }

    /// Builds the readout and, alongside it, the x position of each gap left
    /// for a separator.
    private static func layout(_ segments: [Segment], isDarkMenuBar: Bool) -> (NSAttributedString, [CGFloat]) {
        // Match the size the menu bar uses for everything else, but with
        // monospaced digits so the readout doesn't twitch wider and narrower
        // as the percentages tick over.
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)

        let result = NSMutableAttributedString()
        var separatorCenters: [CGFloat] = []

        for segment in segments {
            if result.length > 0 {
                let start = result.size().width
                result.append(NSAttributedString(
                    string: "   ",
                    attributes: [.font: regularFont, .foregroundColor: neutralColor(isDarkMenuBar)]
                ))
                separatorCenters.append((start + result.size().width) / 2)
            }

            // Both labels carry their provider accent, matching the panel's
            // section headings.
            let labelColor = segment.provider?.accentNSColor(isDark: isDarkMenuBar)
                ?? neutralColor(isDarkMenuBar)
            result.append(NSAttributedString(
                string: segment.label,
                attributes: [.font: boldFont, .foregroundColor: labelColor]
            ))
            result.append(NSAttributedString(
                string: " " + segment.value,
                attributes: [
                    .font: regularFont,
                    .foregroundColor: usageColor(remaining: segment.remaining, isDarkMenuBar: isDarkMenuBar),
                ]
            ))
        }
        return (result, separatorCenters)
    }
}
