import Foundation

/// The HUD has three sizes, and each one is a different claim on your
/// attention: a glance, an interruption, and a decision.
enum HUDMode {
    /// A pill beside the notch. Ambient, ignorable.
    case collapsed
    /// One recommendation, delivered on the HUD's own initiative.
    case notification
    /// The full list, opened because you asked for it.
    case expanded

    var panelWidth: CGFloat {
        switch self {
        case .collapsed: return 92
        case .notification: return 348
        case .expanded: return 400
        }
    }
}
