import SwiftUI

enum FolioMotion {
    static let toolbarMorph = Animation.spring(
        response: 0.34,
        dampingFraction: 1,
        blendDuration: 0.08
    )

    static let pageSwitch = Animation.spring(
        response: 0.38,
        dampingFraction: 1,
        blendDuration: 0.08
    )

    static let press = Animation.easeOut(duration: 0.12)
    static let reduced = Animation.easeOut(duration: 0.18)

    static func toolbarMorph(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : toolbarMorph
    }

    static func pageSwitch(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : pageSwitch
    }
}
