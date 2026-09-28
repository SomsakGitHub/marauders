//
//  PlayerPool.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import Foundation

final class PlayerPool {
    private var players: [URL: AVPlayer] = [:]
    private var accessOrder: [URL] = []
    private var loopTokens: [URL: any NSObjectProtocol] = [:]
    private let capacity: Int

    init(capacity: Int = 3) {
        self.capacity = capacity
    }

    func player(for post: VideoPost) -> AVPlayer? {
        if let cached = players[post.videoURL] {
            touch(post.videoURL)
            return cached
        }

        let asset = AVURLAsset(url: post.videoURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true

        players[post.videoURL] = player
        accessOrder.append(post.videoURL)
        installLoopObserver(for: post.videoURL, player: player)

        evictIfNeeded()
        return player
    }

    func cachedPlayer(for url: URL) -> AVPlayer? {
        players[url]
    }

    func keepAlive(_ posts: [VideoPost]) {
        let kept = Set(posts.map(\.videoURL))
        accessOrder = accessOrder.filter { kept.contains($0) }

        for url in players.keys.map({ $0 }) where !kept.contains(url) {
            release(url)
        }
    }

    func pauseAll(except url: URL?) {
        for (key, player) in players where key != url {
            player.pause()
        }
    }

    private func installLoopObserver(for url: URL, player: AVPlayer) {
        guard let item = player.currentItem else { return }
        let token = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
        loopTokens[url] = token
    }

    private func touch(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func release(_ url: URL) {
        players[url]?.pause()
        players[url] = nil
        accessOrder.removeAll { $0 == url }
        if let token = loopTokens[url] {
            NotificationCenter.default.removeObserver(token)
            loopTokens[url] = nil
        }
    }

    private func evictIfNeeded() {
        while accessOrder.count > capacity {
            release(accessOrder[0])
        }
    }
}
