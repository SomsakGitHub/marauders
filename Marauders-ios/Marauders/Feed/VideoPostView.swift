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
    /// The clip reached its end on its own, which moves the feed forward instead of looping.
    let onDidReachEnd: () -> Void
    /// False while another tab covers the feed. The player is kept so the clip is not
    /// reloaded, but nothing is allowed to make noise from behind an opaque screen.
    var isVisible = true
    /// Bumped by the feed to rewind this clip. Used when the feed has run out and its last clip
    /// has to play again rather than sit frozen.
    var restartToken = 0
    /// Session scoped poster frames, so a clip that has not buffered yet still shows a picture.
    var posters = PosterFrameCache()

    @State private var poster: UIImage?

    @State private var player: AVPlayer?
    @State private var loadState: PlaybackLoadState = .loading
    @State private var isUserPaused = false
    /// Press and hold. Kept apart from `isUserPaused` because a hold never shows the play glyph
    /// and never survives the release.
    @State private var isHolding = false
    @State private var progress: Double = 0
    @State private var hasReportedFailure = false

    @State private var timeToken: Any?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failureToken: (any NSObjectProtocol)?
    @State private var endToken: (any NSObjectProtocol)?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Under the video rather than in place of it. The poster is what is on screen while
            // the player is still buffering, and it disappears under the first real frame rather
            // than fading, so there is no crossfade to notice on every swipe.
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            if let player {
                AmbientVideoBackdrop(player: player)
                    .ignoresSafeArea()
                VideoPlayerSurface(player: player, gravity: .resizeAspect)
                    .ignoresSafeArea()
            }

            statusOverlay

            if intent.showsPlayGlyph {
                Image(systemName: "play.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }

            if intent.showsProgress {
                progressBar
            }
        }
        .contentShape(Rectangle())
        .gesture(tapGesture)
        .onLongPressGesture(minimumDuration: 0.35, perform: {}, onPressingChanged: { pressing in
            handlePress(pressing)
        })
        .onAppear {
            bindPlayer()
        }
        .onDisappear {
            unbindPlayer()
        }
        .onChange(of: isActive) { _, nowActive in
            // Coming back to a clip resumes it. Without this a pause survives the trip away and
            // the viewer returns to a still frame with a play glyph on it.
            if nowActive {
                isUserPaused = false
            }
            syncPlayback()
        }
        .onChange(of: isVisible) { _, _ in
            syncPlayback()
        }
        .onChange(of: restartToken) { _, _ in
            guard isActive, isVisible else { return }
            restart()
        }
        .task(id: post.videoURL) {
            // Asked on appearance, not on becoming active. A clip the viewer is about to scroll
            // into is exactly the one that needs its poster, and waiting until it is on screen
            // is too late to be useful.
            poster = await posters.poster(for: post.videoURL)
        }
        .onChange(of: scenePhase) { _, _ in
            // Coming back from the background has to re-issue the play, because the pool paused
            // every player on the way out and nothing else is holding the intent.
            syncPlayback()
        }
    }

    /// A hairline at the foot of the frame, the way TikTok reports where you are in a clip
    /// without putting a control bar on screen.
    private var progressBar: some View {
        VStack {
            Spacer(minLength: 0)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(proxy.size.width * progress, 0))
                }
            }
            .frame(height: 2)
        }
        .padding(.bottom, 96)
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.1), value: progress)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch loadState {
        case .loading:
            // A spinner over a poster that already shows the clip is noise. It only appears when
            // there is genuinely nothing on screen yet.
            if poster == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white.opacity(0.9))
            }
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
        guard isActive, isVisible else { return }
        isUserPaused.toggle()
        syncPlayback()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A tap and a hold have to be told apart, or a long press would also flip the paused state
    /// on the way up and the clip would end up running after the finger lifts.
    private func handlePress(_ pressing: Bool) {
        guard isActive, isVisible else { return }
        isHolding = pressing
        if pressing {
            isUserPaused = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        syncPlayback()
    }

    private var intent: PlaybackIntent {
        PlaybackIntent(
            isActivePost: isActive,
            isPausedByUser: isUserPaused,
            isHeld: isHolding,
            isFeedVisible: isVisible,
            isAppActive: scenePhase == .active
        )
    }

    private func syncPlayback() {
        guard let player else { return }
        if intent.shouldPlay {
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
        progress = 0
        observeItem(of: bound)
        observeProgress(of: bound)
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
        if let endToken {
            NotificationCenter.default.removeObserver(endToken)
            self.endToken = nil
        }
        pool.detach(from: post)
        player?.pause()
        player = nil
        progress = 0
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

        // A clip that finishes hands the feed forward rather than starting itself over. The
        // player is left paused at the end frame, so if the feed decides to come back to this
        // post it has to restart it deliberately.
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak bound] _ in
            guard bound?.rate != 0 else { return }
            bound?.pause()
            Task { @MainActor in
                guard loadState == .ready else { return }
                onDidReachEnd()
            }
        }
    }

    /// Rewinds to the first frame and hands control back to the play intent.
    ///
    /// The intent is captured by value rather than capturing `self`, because this is a struct and
    /// a seek completion outlives the call. Deciding up front also means a clip rewound while the
    /// feed is covered stays paused instead of starting on its own.
    private func restart() {
        guard let player else { return }
        let shouldResume = intent.shouldPlay
        progress = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                if shouldResume {
                    player.play()
                }
            }
        }
    }

    /// Samples the playhead so the progress hairline can move. This observer is what the
    /// pre-existing teardown in `unbindPlayer` was already cleaning up for.
    private func observeProgress(of bound: AVPlayer) {
        let token = bound.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak bound] _ in
            guard
                let bound,
                let duration = bound.currentItem?.duration,
                duration.isNumeric,
                duration.seconds.isFinite,
                duration.seconds > 0
            else { return }

            let elapsed = bound.currentTime().seconds
            guard elapsed.isFinite else { return }

            Task { @MainActor in
                progress = min(max(elapsed / duration.seconds, 0), 1)
            }
        }
        timeToken = token
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
        isHolding = false
        bindPlayer()
    }
}

#Preview {
    VideoPostView(
        post: VideoPost.samples[0],
        isActive: true,
        pool: PlayerPool(),
        onLoadFailed: {},
        onDidReachEnd: {}
    )
    .ignoresSafeArea()
}
