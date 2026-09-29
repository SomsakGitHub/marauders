//
//  VideoPostView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import SwiftUI

enum PlaybackLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

struct VideoPostView: View {
    let post: VideoPost
    let isActive: Bool
    let pool: PlayerPool
    let onLoadFailed: () -> Void

    @State private var player: AVPlayer?
    @State private var loadState: PlaybackLoadState = .loading
    @State private var isUserPaused = false
    @State private var hasReportedFailure = false

    @State private var timeToken: Any?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failureToken: (any NSObjectProtocol)?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                AmbientVideoBackdrop(player: player)
                    .ignoresSafeArea()
                VideoPlayerSurface(player: player, gravity: .resizeAspect)
                    .ignoresSafeArea()
            }

            statusOverlay

            if isUserPaused && isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .gesture(tapGesture)
        .onAppear {
            bindPlayer()
        }
        .onDisappear {
            unbindPlayer()
        }
        .onChange(of: isActive) { _, _ in
            syncPlayback()
        }
        .onChange(of: scenePhase) { _, _ in
            // Coming back from the background has to re-issue the play, because the pool paused
            // every player on the way out and nothing else is holding the intent.
            syncPlayback()
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.white.opacity(0.9))
        case .failed(let message):
            errorCard(message)
        case .ready:
            EmptyView()
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(.white)

            Text("โหลดวิดีโอไม่สำเร็จ")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Button {
                retry()
            } label: {
                Label("ลองใหม่", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 40)
    }

    private var tapGesture: some Gesture {
        TapGesture().onEnded {
            togglePlayback()
        }
    }

    private func togglePlayback() {
        guard isActive else { return }
        isUserPaused.toggle()
        syncPlayback()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func syncPlayback() {
        guard let player else { return }
        if isActive && !isUserPaused {
            player.play()
        } else {
            player.pause()
        }
    }

    private func bindPlayer() {
        guard player == nil, let bound = pool.attach(to: post) else { return }
        player = bound
        loadState = .loading
        hasReportedFailure = false
        observeItem(of: bound)
        syncPlayback()
    }

    private func unbindPlayer() {
        if let timeToken, let bound = player {
            bound.removeTimeObserver(timeToken)
        }
        timeToken = nil
        if let statusObservation {
            statusObservation.invalidate()
            self.statusObservation = nil
        }
        if let failureToken {
            NotificationCenter.default.removeObserver(failureToken)
            self.failureToken = nil
        }
        pool.detach(from: post)
        player?.pause()
        player = nil
    }

    private func observeItem(of bound: AVPlayer) {
        guard let item = bound.currentItem else {
            loadState = .failed("ไม่พบไฟล์วิดีโอ")
            return
        }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            let state: PlaybackLoadState
            switch item.status {
            case .readyToPlay:
                state = .ready
            case .failed:
                let message = item.error?.localizedDescription ?? "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ"
                state = .failed(message)
            default:
                state = .loading
            }
            Task { @MainActor in
                loadState = state
                if case .failed = state {
                    reportFailure()
                }
            }
        }

        failureToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak bound] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            loadState = .failed(error?.localizedDescription ?? "เล่นวิดีโอไม่สำเร็จ")
            reportFailure()
            bound?.pause()
        }
    }

    /// Reports a broken clip once per attempt so the feed can move on instead of parking the
    /// viewer here. The error card stays for anyone who scrolls back to a dead post on purpose.
    private func reportFailure() {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        onLoadFailed()
    }

    private func retry() {
        unbindPlayer()
        pool.invalidate(post)
        loadState = .loading
        isUserPaused = false
        bindPlayer()
    }
}

#Preview {
    VideoPostView(
        post: VideoPost.samples[0],
        isActive: true,
        pool: PlayerPool(),
        onLoadFailed: {}
    )
    .ignoresSafeArea()
}
