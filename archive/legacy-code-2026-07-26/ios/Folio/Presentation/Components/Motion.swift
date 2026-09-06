import SwiftUI

enum Motion {
    /// Settle: elements land with weight, near-zero bounce
    static let settle = Animation.spring(duration: 0.4, bounce: 0.05)

    /// Quick: immediate button/state feedback
    static let quick = Animation.spring(duration: 0.25, bounce: 0.0)

    /// Ink: content appears as if printed — fast easeOut
    static let ink = Animation.easeOut(duration: 0.15)

    /// Exit: elements leave quietly
    static let exit = Animation.easeIn(duration: 0.2)

    /// Slow: progress bars, processing state
    static let slow = Animation.linear(duration: 2.0)

    /// Returns nil (instant) when Reduce Motion is enabled; otherwise the given animation.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .none : animation
    }
}
