//
//  PosterFrameCacheTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation
import Testing
import UIKit
@testable import Marauders

private let firstURL = URL(string: "https://example.invalid/first.mp4")!
private let secondURL = URL(string: "https://example.invalid/second.mp4")!

private func makePoster(_ color: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
    return renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
}

@Suite("PosterFrameCache")
struct PosterFrameCacheTests {

    @Test("a poster is produced once and then served from cache")
    func cachesProducedPoster() async throws {
        let counter = CallCounter()
        let cache = PosterFrameCache(generator: { url in
            counter.record(url)
            return makePoster(.red)
        })

        let first = try await cache.poster(for: firstURL)
        let second = try await cache.poster(for: firstURL)

        #expect(first != nil)
        #expect(second != nil)
        #expect(counter.count(for: firstURL) == 1)
    }

    @Test("a poster already in the cache is returned without calling the generator")
    func cachedPosterSkipsWork() async throws {
        let counter = CallCounter()
        let cache = PosterFrameCache(generator: { url in
            counter.record(url)
            return makePoster(.red)
        })

        _ = try await cache.poster(for: firstURL)
        let cached = await cache.cachedPoster(for: firstURL)
        let after = counter.count(for: firstURL)
        let again = try await cache.poster(for: firstURL)

        #expect(cached != nil)
        #expect(again != nil)
        // Asking again after the frame is cached must not touch the generator at all.
        #expect(counter.count(for: firstURL) == after)
    }

    @Test("two callers asking at the same time share one generation")
    func concurrentRequestsShareWork() async throws {
        let counter = CallCounter()
        let cache = PosterFrameCache(generator: { url in
            counter.record(url)
            try await Task.sleep(for: .milliseconds(40))
            return makePoster(.blue)
        })

        async let a = cache.poster(for: firstURL)
        async let b = cache.poster(for: firstURL)
        let results = await [a, b]

        #expect(results.allSatisfy { $0 != nil })
        #expect(counter.count(for: firstURL) == 1)
    }

    @Test("a clip that cannot give up a frame is not retried on every swipe")
    func failuresAreNotRetried() async throws {
        let counter = CallCounter()
        let cache = PosterFrameCache(generator: { url in
            counter.record(url)
            throw URLError(.unsupportedURL)
        })

        #expect(await cache.poster(for: firstURL) == nil)
        #expect(await cache.hasFailed(for: firstURL))
        #expect(await cache.poster(for: firstURL) == nil)
        #expect(counter.count(for: firstURL) == 1)
    }

    @Test("a failure is remembered per clip, not globally")
    func failuresAreScopedToTheirClip() async throws {
        let cache = PosterFrameCache(generator: { url in
            if url == firstURL { throw URLError(.unsupportedURL) }
            return makePoster(.green)
        })

        #expect(await cache.poster(for: firstURL) == nil)
        #expect(await cache.hasFailed(for: secondURL) == false)
        #expect(await cache.poster(for: secondURL) != nil)
    }

    @Test("the cache stays bounded and keeps what it was just given")
    func evictsOldestBeyondLimit() async throws {
        let cache = PosterFrameCache(generator: { _ in makePoster(.red) }, limit: 2)

        _ = try await cache.poster(for: firstURL)
        _ = try await cache.poster(for: secondURL)
        _ = try await cache.poster(for: URL(string: "https://example.invalid/third.mp4")!)

        #expect(await cache.cachedPoster(for: firstURL) == nil)
        #expect(await cache.cachedPoster(for: secondURL) != nil)
        #expect(await cache.cachedPoster(for: URL(string: "https://example.invalid/third.mp4")!) != nil)
    }

    @Test("an unknown clip has nothing cached and is not marked as failed")
    func unknownClipIsUntouched() async {
        let cache = PosterFrameCache(generator: { _ in makePoster(.red) })

        #expect(await cache.cachedPoster(for: firstURL) == nil)
        #expect(await cache.hasFailed(for: firstURL) == false)
    }
}

/// Counts generator calls per clip. The generator is `@Sendable` and runs off the main actor,
/// so this has to be safe to touch from more than one task.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]

    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        counts[url, default: 0] += 1
    }

    func count(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[url] ?? 0
    }
}