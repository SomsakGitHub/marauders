//
//  PlaybackIntent.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation

/// Whether one clip should be running right now.
///
/// Pulled out of `VideoPostView` because the rule has more inputs than it looks like it should:
/// a clip that the viewer has paused, a finger that is still down, a tab that is covering the
/// feed and an app in the background all have to agree, and the combination is easy to get
/// wrong in a gesture handler where none of it can be exercised.
struct PlaybackIntent: Equatable {
    /// This is the post the feed is scrolled to.
    let isActivePost: Bool
    /// The viewer tapped the clip to park it.
    let isPausedByUser: Bool
    /// A finger is down on the clip.
    let isHeld: Bool
    /// The feed is on screen. False while the upload tab covers it.
    let isFeedVisible: Bool
    let isAppActive: Bool

    var shouldPlay: Bool {
        isActivePost && !isPausedByUser && !isHeld && isFeedVisible && isAppActive
    }

    /// The play glyph belongs to a pause the viewer chose, not to a hold and not to a clip they
    /// cannot currently see. Showing it otherwise would be telling them to tap a video that is
    /// already running or already off screen.
    ///
    /// A hold clears `isPausedByUser` on the way down, so the two never both hold in practice.
    /// The `isHeld` term is here so the rule stays true for every combination rather than only
    /// the ones the gesture handler currently happens to produce.
    var showsPlayGlyph: Bool {
        isPausedByUser && !isHeld && isActivePost && isFeedVisible
    }

    /// The progress hairline describes the clip in front of you, so it is hidden when it is not
    /// in front of you.
    var showsProgress: Bool {
        isActivePost && isFeedVisible
    }
}
