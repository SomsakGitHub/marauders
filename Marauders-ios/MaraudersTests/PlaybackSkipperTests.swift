//
//  PlaybackSkipperTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation
import Testing
@testable import Marauders

@Suite("PlaybackSkipper")
struct PlaybackSkipperTests {

    @Test("the next post is chosen when there is one")
    func picksNextPost() throws {
        let next = try #require(
            PlaybackSkipper.next(after: "a", in: ["a", "b", "c"], skipping: ["a"])
        )

        #expect(next == "b")
    }

    @Test("a failed post is skipped in favour of a playable one")
    func skipsFailedPosts() throws {
        let next = try #require(
            PlaybackSkipper.next(after: "a", in: ["a", "b", "c"], skipping: ["a", "b"])
        )

        #expect(next == "c")
    }

    @Test("there is nothing after the last post")
    func lastPostHasNoNext() {
        #expect(PlaybackSkipper.next(after: "c", in: ["a", "b", "c"], skipping: ["c"]) == nil)
    }

    @Test("a post that is not in the feed yields nothing")
    func unknownPostHasNoNext() {
        #expect(PlaybackSkipper.next(after: "z", in: ["a", "b"], skipping: []) == nil)
    }

    @Test("a single post feed has no next post")
    func singlePostFeedHasNoNext() {
        #expect(PlaybackSkipper.next(after: "a", in: ["a"], skipping: []) == nil)
    }
}

@Suite("PlaybackSkipper.Move")
struct PlaybackSkipperMoveTests {

    @Test("a clip that ended advances to the next post")
    func endAdvances() {
        let move = PlaybackSkipper.move(
            after: "a",
            in: ["a", "b", "c"],
            skipping: [],
            hasMore: false
        )

        #expect(move == .advance(to: "b"))
    }

    @Test("a clip that ended skips over posts that cannot play")
    func endSkipsFailedPosts() {
        let move = PlaybackSkipper.move(
            after: "a",
            in: ["a", "b", "c"],
            skipping: ["b"],
            hasMore: false
        )

        #expect(move == .advance(to: "c"))
    }

    @Test("the last clip asks for another page when the server says one exists")
    func lastClipWantsAnotherPage() {
        let move = PlaybackSkipper.move(
            after: "c",
            in: ["a", "b", "c"],
            skipping: [],
            hasMore: true
        )

        #expect(move == .needsMoreClips)
    }

    @Test("the last clip is exhausted when no page remains")
    func lastClipIsExhausted() {
        let move = PlaybackSkipper.move(
            after: "c",
            in: ["a", "b", "c"],
            skipping: [],
            hasMore: false
        )

        #expect(move == .exhausted(at: "c"))
    }

    @Test("a clip that failed on the tail still pulls a page, since the next one may play")
    func failedTailPullsMore() {
        let move = PlaybackSkipper.move(
            after: "b",
            in: ["a", "b"],
            skipping: ["b"],
            hasMore: true
        )

        #expect(move == .needsMoreClips)
    }

    @Test("a clip that failed does not ask for another page it cannot use")
    func failedTailDoesNotPullPages() {
        // "c" failed too, so loading another page would only produce more dead clips. The feed
        // stops where it is instead of paging blindly.
        let move = PlaybackSkipper.move(
            after: "b",
            in: ["a", "b", "c"],
            skipping: ["b", "c"],
            hasMore: true
        )

        #expect(move == .exhausted(at: "b"))
    }

    @Test("a single clip feed is exhausted as soon as it ends")
    func singleClipFeedIsExhausted() {
        let move = PlaybackSkipper.move(
            after: "a",
            in: ["a"],
            skipping: [],
            hasMore: false
        )

        #expect(move == .exhausted(at: "a"))
    }

    @Test("a single clip feed with more pages available asks for them")
    func singleClipFeedPullsMore() {
        let move = PlaybackSkipper.move(
            after: "a",
            in: ["a"],
            skipping: [],
            hasMore: true
        )

        #expect(move == .needsMoreClips)
    }

    @Test("a post that vanished from the feed is reported as exhausted rather than crashing")
    func unknownPostIsExhausted() {
        let move = PlaybackSkipper.move(
            after: "z",
            in: ["a", "b"],
            skipping: [],
            hasMore: true
        )

        #expect(move == .exhausted(at: "z"))
    }

    @Test("ending a clip never lands back on the clip that ended")
    func neverRevisitsTheSameClip() {
        let ids = ["a", "b", "c"]
        let move = PlaybackSkipper.move(
            after: "b",
            in: ids,
            skipping: [],
            hasMore: false
        )

        if case .advance(let next) = move {
            #expect(next != "b")
        } else {
            Issue.record("expected an advance, got \(move)")
        }
    }
}