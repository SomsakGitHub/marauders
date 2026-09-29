//
//  PlayerPoolTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import Foundation
import Testing
@testable import Marauders

private func makePost(_ name: String) -> VideoPost {
    VideoPost(
        id: name,
        videoURL: URL(string: "https://example.invalid/\(name).m3u8")!,
        author: PostAuthor(id: name, handle: "@\(name)", displayName: name, emoji: "⚡", isVerified: false),
        caption: name,
        music: "original sound",
        likes: 1,
        comments: 1,
        saves: 1,
        shares: 1
    )
}

@Suite("PlayerPool")
struct PlayerPoolTests {

    @Test("attach returns the same cached player for repeated requests")
    func attachCachesPlayer() throws {
        let pool = PlayerPool(capacity: 3)
        let post = makePost("a")

        let first = try #require(pool.attach(to: post))
        let second = try #require(pool.attach(to: post))

        #expect(first === second)
        #expect(pool.cachedPlayer(for: post.videoURL) === first)
    }

    @Test("warm evicts the least recently used player beyond capacity")
    func warmEvictsLeastRecentlyUsed() throws {
        let pool = PlayerPool(capacity: 2)
        let posts = [makePost("a"), makePost("b"), makePost("c")]

        pool.warm(posts)

        #expect(pool.cachedPlayer(for: posts[0].videoURL) == nil)
        #expect(pool.cachedPlayer(for: posts[1].videoURL) != nil)
        #expect(pool.cachedPlayer(for: posts[2].videoURL) != nil)
    }

    @Test("attaching again refreshes recency so the active player survives eviction")
    func attachRefreshesRecency() throws {
        let pool = PlayerPool(capacity: 2)
        let posts = [makePost("a"), makePost("b"), makePost("c")]

        _ = pool.attach(to: posts[0])
        pool.warm(posts)

        #expect(pool.cachedPlayer(for: posts[0].videoURL) != nil)
        #expect(pool.cachedPlayer(for: posts[1].videoURL) == nil)
    }

    @Test("pinned players are never evicted by warm")
    func pinnedPlayersSurviveEviction() throws {
        let pool = PlayerPool(capacity: 1)
        let posts = [makePost("a"), makePost("b"), makePost("c")]
        let pinnedPlayer = try #require(pool.attach(to: posts[0]))

        pool.warm(posts)

        #expect(pool.cachedPlayer(for: posts[0].videoURL) === pinnedPlayer)
        #expect(pool.cachedPlayer(for: posts[1].videoURL) == nil)
        #expect(pool.cachedPlayer(for: posts[2].videoURL) == nil)
    }

    @Test("detach releases the pin and lets the player be evicted")
    func detachReleasesPin() throws {
        let pool = PlayerPool(capacity: 1)
        let post = makePost("a")

        _ = pool.attach(to: post)
        pool.detach(from: post)
        pool.warm([post, makePost("b")])

        #expect(pool.cachedPlayer(for: post.videoURL) == nil)
    }

    @Test("invalidate drops the cached player")
    func invalidateDropsPlayer() throws {
        let pool = PlayerPool(capacity: 3)
        let post = makePost("a")

        _ = pool.attach(to: post)
        pool.invalidate(post)

        #expect(pool.cachedPlayer(for: post.videoURL) == nil)
    }

    @Test("mute applies to every cached player and to players created later")
    func muteIsForwarded() throws {
        let pool = PlayerPool(capacity: 3)
        let first = makePost("a")
        let second = makePost("b")
        let firstPlayer = try #require(pool.attach(to: first))

        pool.setMuted(true)
        let secondPlayer = try #require(pool.attach(to: second))

        #expect(firstPlayer.isMuted)
        #expect(secondPlayer.isMuted)
        #expect(pool.isMuted)

        pool.setMuted(false)

        #expect(!firstPlayer.isMuted)
        #expect(!secondPlayer.isMuted)
    }
}

@Suite("VideoPost")
struct VideoPostTests {

    @Test("compact counts stay non empty for zero and large values")
    func compactFormatting() {
        #expect(Int(0).compact == "0")
        #expect(!Int(128_400).compact.isEmpty)
        #expect(!Int(2_310_000).compact.isEmpty)
    }

    @Test("sample feed has unique identifiers and https sources")
    func sampleFeedIntegrity() {
        let samples = VideoPost.samples

        #expect(!samples.isEmpty)
        #expect(Set(samples.map(\.id)).count == samples.count)
        for post in samples {
            #expect(post.videoURL.scheme == "https")
        }
    }
}
