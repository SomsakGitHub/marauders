//
//  PlaybackSkipper.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation

/// Decides which clip the feed lands on once the current one stops being watchable, either
/// because it played to the end or because it could not play at all.
enum PlaybackSkipper {
    /// The next post id to try, or `nil` when there is nothing playable left in the list.
    ///
    /// - Parameters:
    ///   - postID: The post that just failed.
    ///   - postIDs: Every post currently in the feed, in display order.
    ///   - failed: Posts already known to be unplayable, including `postID`.
    static func next(after postID: String, in postIDs: [String], skipping failed: Set<String>) -> String? {
        guard let index = postIDs.firstIndex(of: postID) else { return nil }
        guard index + 1 < postIDs.count else { return nil }
        let remaining = postIDs[postIDs.index(after: index)...]
        return remaining.first { !failed.contains($0) }
    }

    /// What the feed should do once a clip has run out. A clip that reached its end advances the
    /// feed; a clip that failed is remembered so nothing goes back to it.
    enum Move: Equatable {
        /// Show this post next.
        case advance(to: String)
        /// The last loaded clip is done and the page boundary may still be hiding more.
        case needsMoreClips
        /// Nothing playable left. `postID` is where the feed is parked.
        case exhausted(at: String)
    }

    /// Resolves the end of a clip into the next move, reusing the same "skip what is broken" rule
    /// that playback failures use.
    ///
    /// - Parameters:
    ///   - postID: The post that just ended or failed.
    ///   - postIDs: Every post currently in the feed, in display order.
    ///   - failed: Posts already known to be unplayable.
    ///   - hasMore: Whether the server says another page exists past what is loaded.
    static func move(
        after postID: String,
        in postIDs: [String],
        skipping failed: Set<String>,
        hasMore: Bool
    ) -> Move {
        guard let index = postIDs.firstIndex(of: postID) else { return .exhausted(at: postID) }

        if let next = next(after: postID, in: postIDs, skipping: failed) {
            return .advance(to: next)
        }

        // The clip that ended was the last one loaded. Whether the feed is really over depends
        // on the page boundary, not on this list.
        if hasMore && index >= postIDs.count - 1 {
            return .needsMoreClips
        }

        return .exhausted(at: postID)
    }
}
