import SwiftUI

enum FolioMotion {
    static let toolbarMorph = Animation.spring(
        response: 0.26,
        dampingFraction: 1,
        blendDuration: 0.05
    )

    static let pageSwitch = Animation.spring(
        response: 0.38,
        dampingFraction: 1,
        blendDuration: 0.08
    )

    static let segmentSelection = Animation.spring(
        response: 0.24,
        dampingFraction: 1,
        blendDuration: 0.04
    )

    static let articleContentSwitch = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.2
    )

    static let chromeVisibility = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.16
    )

    static let backSwipeCompletion = Animation.timingCurve(
        0.2,
        0,
        0,
        1,
        duration: 0.18
    )

    static let backSwipeCancellation = Animation.spring(
        response: 0.24,
        dampingFraction: 0.86,
        blendDuration: 0
    )

    static let press = Animation.easeOut(duration: 0.12)
    static let reduced = Animation.easeOut(duration: 0.18)

    static func toolbarMorph(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : toolbarMorph
    }

    static func pageSwitch(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : pageSwitch
    }

    static func segmentSelection(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : segmentSelection
    }

    static func articleContentSwitch(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : articleContentSwitch
    }

    static func chromeVisibility(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : chromeVisibility
    }

    static func backSwipeCompletion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : backSwipeCompletion
    }

    static func backSwipeCancellation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : backSwipeCancellation
    }
}
