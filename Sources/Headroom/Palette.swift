import AppKit
import HeadroomCore

/// The HUD lives against the black of the notch, so the world is built up
/// from that black rather than tinted down toward it.
enum Palette {
    static let shell = NSColor(srgbRed: 0.031, green: 0.035, blue: 0.043, alpha: 1)
    static let hairline = NSColor(white: 1, alpha: 0.10)
    static let rowHover = NSColor(white: 1, alpha: 0.055)
    static let track = NSColor(white: 1, alpha: 0.12)

    static let primary = NSColor(white: 0.96, alpha: 1)
    static let secondary = NSColor(white: 0.58, alpha: 1)
    static let tertiary = NSColor(white: 0.56, alpha: 1)

    static let comfortable = NSColor(srgbRed: 0.31, green: 0.82, blue: 0.51, alpha: 1)
    static let warn = NSColor(srgbRed: 1.00, green: 0.71, blue: 0.16, alpha: 1)
    static let critical = NSColor(srgbRed: 1.00, green: 0.35, blue: 0.29, alpha: 1)

    static func color(for level: PressureLevel) -> NSColor {
        switch level {
        case .comfortable: return comfortable
        case .warn: return warn
        case .critical: return critical
        }
    }

    /// The headline states how the machine is *doing*, which is no longer the
    /// same as how much memory is in use. A Mac at 90% with nothing moving is
    /// healthy, and saying otherwise was the old model's central mistake.
    static func headline(for level: PressureLevel) -> String {
        switch level {
        case .comfortable: return "Memory is healthy"
        case .warn: return "Memory is under strain"
        case .critical: return "Your Mac is struggling"
        }
    }
}

enum Type {
    static func text(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    /// Tabular figures so the live numbers do not jitter as they change.
    static func number(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]
        ])
        return NSFont(descriptor: desc, size: size) ?? base
    }
}
