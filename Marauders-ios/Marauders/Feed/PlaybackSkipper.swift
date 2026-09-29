//
//  PlaybackSkipper.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation

/// Picks which clip to show after the current one turns out to be unplayable, so a dead URL
/// costs the viewer a moment instead of parking them on an error card.
enum PlaybackSkipper {
    /// The next post id to try, or `nil` when there is nothing playable left in the list.
    ///
    /// - Parameters:
    ///   - postID: The post that just failed.
    ///   - postIDs: Every post currently in the feed, in display order.
    ///   - failed: Posts already known to be unplayable, including `postID`.
    static func next(after postID: String, in postIDs: [String], skipping failed: Set<String>) -> String? {
        guard let index = postIDs.firstIndex(of: postID) else { return nil }
        let remaining = postIDs[postIDs.index(after: index)...]
        return remaining.first { !failed.contains($0) }
    }
}
