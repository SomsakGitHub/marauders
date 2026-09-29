//
//  PlaybackIntentTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation
import Testing
@testable import Marauders

private func intent(
    isActivePost: Bool = true,
    isPausedByUser: Bool = false,
    isHeld: Bool = false,
    isFeedVisible: Bool = true,
    isAppActive: Bool = true
) -> PlaybackIntent {
    PlaybackIntent(
        isActivePost: isActivePost,
        isPausedByUser: isPausedByUser,
        isHeld: isHeld,
        isFeedVisible: isFeedVisible,
        isAppActive: isAppActive
    )
}

@Suite("PlaybackIntent")
struct PlaybackIntentTests {

    @Test("the clip in front of the viewer plays")
    func activeClipPlays() {
        #expect(intent().shouldPlay)
    }

    @Test("a tap pauses and a second tap resumes")
    func tapTogglesPlayback() {
        #expect(!intent(isPausedByUser: true).shouldPlay)
        #expect(intent(isPausedByUser: false).shouldPlay)
    }

    @Test("a hold parks the clip without leaving a paused state behind")
    func holdParksWithoutPausing() {
        let held = intent(isHeld: true)

        #expect(!held.shouldPlay)
        #expect(!held.showsPlayGlyph)
    }

    @Test("a clip that is not the one on screen stays silent")
    func inactiveClipDoesNotPlay() {
        #expect(!intent(isActivePost: false).shouldPlay)
    }

    @Test("a covered feed plays nothing")
    func coveredFeedIsSilent() {
        let covered = intent(isFeedVisible: false)

        #expect(!covered.shouldPlay)
        #expect(!covered.showsPlayGlyph)
        #expect(!covered.showsProgress)
    }

    @Test("a backgrounded app plays nothing")
    func backgroundedAppIsSilent() {
        #expect(!intent(isAppActive: false).shouldPlay)
    }

    @Test("the play glyph only appears for a pause the viewer chose")
    func playGlyphTracksUserPause() {
        #expect(intent(isPausedByUser: true).showsPlayGlyph)
        #expect(!intent(isPausedByUser: true, isHeld: true).showsPlayGlyph)
        #expect(!intent(isPausedByUser: true, isFeedVisible: false).showsPlayGlyph)
        #expect(!intent(isPausedByUser: false).showsPlayGlyph)
    }

    @Test("the progress hairline tracks the clip in front of the viewer")
    func progressTracksActiveClip() {
        #expect(intent().showsProgress)
        #expect(!intent(isActivePost: false).showsProgress)
        #expect(!intent(isFeedVisible: false).showsProgress)
        #expect(intent(isPausedByUser: true).showsProgress)
    }

    @Test("only the current clip ever plays, whatever else is going on")
    func onlyOneClipPlaysAtATime() {
        let states = [
            intent(),
            intent(isPausedByUser: true),
            intent(isHeld: true),
            intent(isFeedVisible: false),
            intent(isAppActive: false),
            intent(isActivePost: false)
        ]

        #expect(states.filter(\.shouldPlay).count == 1)
    }
}
