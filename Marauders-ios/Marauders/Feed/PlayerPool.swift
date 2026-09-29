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
    private var pinned: Set<URL> = []
    private var loopTokens: [URL: any NSObjectProtocol] = [:]
    private var sessionTokens: [any NSObjectProtocol] = []
    private var activeURL: URL?
    private let capacity: Int
    private(set) var isMuted = false

    init(capacity: Int = 4) {
        self.capacity = capacity
        observeSessionEvents()
    }

    deinit {
        for token in loopTokens.values {
            NotificationCenter.default.removeObserver(token)
        }
        for token in sessionTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func attach(to post: VideoPost) -> AVPlayer? {
        pinned.insert(post.videoURL)
        let player = resolve(post)
        evictIfNeeded()
        return player
    }

    func detach(from post: VideoPost) {
        pinned.remove(post.videoURL)
    }

    func activate(_ post: VideoPost?) {
        guard let post else { return }
        activeURL = post.videoURL
        pauseAll(except: post.videoURL)
    }

    func warm(_ posts: [VideoPost]) {
        for post in posts {
            _ = resolve(post)
        }
        evictIfNeeded()
    }

    func invalidate(_ post: VideoPost) {
        release(post.videoURL)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        for player in players.values {
            player.isMuted = muted
        }
    }

    func cachedPlayer(for url: URL) -> AVPlayer? {
        players[url]
    }

    func pauseAll(except url: URL?) {
        for (key, player) in players where key != url {
            player.pause()
        }
    }

    private func resolve(_ post: VideoPost) -> AVPlayer? {
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
        player.isMuted = isMuted

        players[post.videoURL] = player
        accessOrder.append(post.videoURL)
        installLoopObserver(for: post.videoURL, player: player)
        return player
    }

    private func installLoopObserver(for url: URL, player: AVPlayer) {
        guard let item = player.currentItem else { return }
        let token = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            let wasPlaying = player.rate != 0
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if wasPlaying {
                    player.play()
                }
            }
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
        while players.count > capacity {
            guard let victim = accessOrder.first(where: { !pinned.contains($0) }) else { return }
            release(victim)
        }
    }

    private func observeSessionEvents() {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw),
                let activeURL = self.activeURL,
                let player = self.players[activeURL]
            else { return }

            switch type {
            case .began:
                player.pause()
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                if options.contains(.shouldResume) {
                    player.play()
                }
            @unknown default:
                break
            }
        }

        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                let activeURL = self.activeURL
            else { return }

            if reason == .oldDeviceUnavailable {
                self.players[activeURL]?.pause()
            }
        }

        sessionTokens = [interruption, routeChange]
    }
}
