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

    /// The pill tucks against whichever side of the notch the user prefers.
    func collapsedFrame() -> CGRect {
        let size = collapsedSize
        let x = Settings.side == "left"
            ? notchRect.minX - size.width - 6
            : notchRect.maxX + 6
        return CGRect(x: x, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    func expandedFrame(contentHeight: CGFloat, width: CGFloat = 400) -> CGRect {
        let height = stripHeight + contentHeight
        var x = notchRect.midX - width / 2
        // Keep it on screen if the notch sits near an edge.
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - width - 8)
        return CGRect(x: x, y: screen.frame.maxY - height, width: width, height: height)
    }
}
