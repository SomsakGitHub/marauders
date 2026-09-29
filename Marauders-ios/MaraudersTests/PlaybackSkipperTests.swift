//
//  PlaybackSkipperTests.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Testing
@testable import Marauders

@Suite("PlaybackSkipper")
struct PlaybackSkipperTests {
    private let feed = ["a", "b", "c", "d"]

    @Test("the next playable post is the one after the failure")
    func picksImmediateNeighbour() {
        #expect(PlaybackSkipper.next(after: "a", in: feed, skipping: ["a"]) == "b")
        #expect(PlaybackSkipper.next(after: "b", in: feed, skipping: ["b"]) == "c")
    }

    @Test("already broken posts are stepped over")
    func stepsOverFailures() {
        #expect(PlaybackSkipper.next(after: "a", in: feed, skipping: ["a", "b"]) == "c")
        #expect(PlaybackSkipper.next(after: "a", in: feed, skipping: ["a", "b", "c"]) == "d")
    }

    @Test("the tail has nowhere to go, which is the signal to stop skipping")
    func returnsNilAtTail() {
        #expect(PlaybackSkipper.next(after: "d", in: feed, skipping: ["d"]) == nil)
    }

    @Test("a run of consecutive failures still lands on a playable post")
    func returnsNilWhenNothingPlayableIsLeft() {
        #expect(PlaybackSkipper.next(after: "a", in: feed, skipping: ["a", "b", "c", "d"]) == nil)
        #expect(PlaybackSkipper.next(after: "b", in: feed, skipping: ["a", "b", "c", "d"]) == nil)
    }

    @Test("a post that is not in the feed is ignored")
    func ignoresUnknownPost() {
        #expect(PlaybackSkipper.next(after: "zz", in: feed, skipping: []) == nil)
    }

    @Test("an empty feed never picks anything")
    func handlesEmptyFeed() {
        #expect(PlaybackSkipper.next(after: "a", in: [], skipping: []) == nil)
    }
}
