import AppKit

/// Where the notch is, and where the HUD sits relative to it.
struct NotchGeometry {
    let screen: NSScreen
    let stripHeight: CGFloat   // menu bar / safe area height
    let notchRect: CGRect      // in screen coordinates
    let hasRealNotch: Bool

    static func current() -> NotchGeometry {
        // Prefer the built-in display, which is the one that has a notch.
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let strip = max(screen.safeAreaInsets.top, 24)
        let top = screen.frame.maxY

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            return NotchGeometry(
                screen: screen,
                stripHeight: strip,
                notchRect: CGRect(x: left.maxX, y: top - strip, width: right.minX - left.maxX, height: strip),
                hasRealNotch: true
            )
        }

        // No notch: pretend there is one, centered, so the HUD reads the same.
        let width: CGFloat = 180
        return NotchGeometry(
            screen: screen,
            stripHeight: strip,
            notchRect: CGRect(x: screen.frame.midX - width / 2, y: top - strip, width: width, height: strip),
            hasRealNotch: false
        )
    }

    var collapsedSize: CGSize { CGSize(width: 92, height: stripHeight) }

    /// The pill sits beside the notch by default, or wherever it was dragged.
    func collapsedFrame() -> CGRect {
        let size = collapsedSize
        let fallback = Settings.side == "left"
            ? notchRect.minX - size.width - 6
            : notchRect.maxX + 6
        let x = clampX(Settings.pillX ?? fallback, width: size.width)
        return CGRect(x: x, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x, screen.frame.minX + 4), screen.frame.maxX - width - 4)
    }

    func expandedFrame(contentHeight: CGFloat, width: CGFloat = 400) -> CGRect {
        let height = stripHeight + contentHeight
        // The panel hangs from the notch, but never so far from the pill that
        // the two read as unrelated. Dragged far enough away, it stops spanning
        // the notch and the cutout drops away on its own.
        var x = notchRect.midX - width / 2
        let pill = collapsedFrame().midX
        let tether: CGFloat = 48
        if pill < x + tether { x = pill - tether }
        if pill > x + width - tether { x = pill - width + tether }
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - width - 8)
        return CGRect(x: x, y: screen.frame.maxY - height, width: width, height: height)
    }
}
