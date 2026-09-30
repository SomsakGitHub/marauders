//
//  PosterFrameCache.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import AVFoundation
import Foundation
import UIKit

/// Generates the first frame of a clip. Injected so the cache can be tested without a network.
typealias PosterGenerator = @Sendable (URL) async throws -> UIImage

/// Holds one poster frame per clip so scrolling shows a picture instead of a black screen.
///
/// A vertical feed spends most of its time showing a clip that has not buffered yet. Without a
/// poster that is a black rectangle and a spinner on every swipe, which is the difference
/// between a feed that feels instant and one that feels like it is thinking.
///
/// The frames are produced on demand from the clip itself rather than stored by the server, so
/// this needs no migration and no upload change. The cost is decoding the first frame once per
/// clip per session, which is why results are kept: the same clip is scrolled past repeatedly.
actor PosterFrameCache {
    private var frames: [URL: UIImage] = [:]
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var misses: Set<URL> = []

    private let generator: PosterGenerator
    private let limit: Int

    init(generator: @escaping PosterGenerator = PosterFrameCache.avFoundationGenerator, limit: Int = 12) {
        self.generator = generator
        self.limit = limit
    }

    /// The poster if it has already been produced, without starting any work.
    func cachedPoster(for url: URL) -> UIImage? {
        frames[url]
    }

    /// Whether this clip has already failed to produce a frame. Asked once per clip so a URL that
    /// cannot give up a frame is not retried on every swipe.
    func hasFailed(for url: URL) -> Bool {
        misses.contains(url)
    }

    /// Produces the poster for a clip unless it is already cached, already being produced, or
    /// already known to be impossible.
    func poster(for url: URL) async -> UIImage? {
        if let existing = frames[url] {
            return existing
        }
        if misses.contains(url) {
            return nil
        }
        if let running = inFlight[url] {
            return await running.value
        }

        let task = Task<UIImage?, Never> { [generator] in
            try? await generator(url)
        }
        inFlight[url] = task

        let image = await task.value
        inFlight[url] = nil

        if let image {
            store(image, for: url)
        } else {
            misses.insert(url)
        }
        return image
    }

    private func store(_ image: UIImage, for url: URL) {
        frames[url] = image
        guard frames.count > limit else { return }

        // Evict in insertion order, which is close enough to age for a session-scoped cache and
        // avoids tracking access the way the player pool does. The keys are copied out first
        // because the collection is being read while the dictionary is being written.
        let excess = frames.count - limit
        let victims = Array(frames.keys).prefix(excess)
        for key in victims {
            frames[key] = nil
        }
    }

    /// Pulls frame zero out of the clip with the same orientation handling the player uses, so a
    /// portrait clip does not come back rotated.
    static let avFoundationGenerator: PosterGenerator = { url in
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let (image, _) = try await generator.image(at: .zero)
        return UIImage(cgImage: image)
    }
}