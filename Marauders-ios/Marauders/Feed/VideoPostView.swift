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
    let onToggleLike: () -> Void
    let onToggleSave: () -> Void

    @State private var player: AVPlayer?
    @State private var loadState: PlaybackLoadState = .loading
    @State private var isMuted = false
    @State private var isUserPaused = false
    @State private var showHeartBurst = false
    @State private var isDiscSpinning = false
    @State private var progress: Double = 0

    @State private var timeToken: Any?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failureToken: (any NSObjectProtocol)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayerSurface(player: player)
                    .ignoresSafeArea()
            }

            statusOverlay

            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if isUserPaused && isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }

            if showHeartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.red)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                topBar
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    captionBlock
                    Spacer(minLength: 0)
                    actionRail
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 92)
            }
            .padding(.top, 8)

            progressBar
        }
        .contentShape(Rectangle())
        .gesture(tapGesture)
        .onAppear {
            isDiscSpinning = true
            bindPlayer()
        }
        .onDisappear {
            unbindPlayer()
        }
        .onChange(of: isActive) { _, _ in
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

    private var topBar: some View {
        HStack(spacing: 20) {
            Text("Following")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("For You")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 28, height: 3)
                        .offset(y: 6)
                }

            Spacer()

            Button {
                isMuted.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(post.author.handle)
                    .font(.headline.weight(.bold))
                if post.author.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
            }
            .foregroundStyle(.white)

            Text(post.caption)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(3)

            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.caption2)
                Text(post.music)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
        }
    }

    private var actionRail: some View {
        VStack(spacing: 20) {
            avatar

            railButton(
                icon: post.isLiked ? "heart.fill" : "heart",
                tint: post.isLiked ? .red : .white,
                count: post.likes
            ) {
                onToggleLike()
            }

            railButton(icon: "bubble.right.fill", count: post.comments) {}

            railButton(
                icon: post.isSaved ? "bookmark.fill" : "bookmark",
                count: post.saves
            ) {
                onToggleSave()
            }

            railButton(icon: "arrowshape.turn.up.right.fill", count: post.shares) {}

            musicDisc
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottom) {
            Text(post.author.emoji)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(Color(.systemGray5), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))

            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.red, in: Circle())
                .overlay(Circle().stroke(.black, lineWidth: 2))
                .offset(y: 8)
        }
        .padding(.bottom, 10)
    }

    private var musicDisc: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray3))
                .frame(width: 44, height: 44)
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .rotationEffect(.degrees(isDiscSpinning ? 360 : 0))
        .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: isDiscSpinning)
    }

    private func railButton(
        icon: String,
        tint: Color = .white,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
                Text(count.compact)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 2.5)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Rectangle()
                                .fill(.white)
                                .frame(width: bar.size.width * progress)
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                switch result {
                case .first:
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                        showHeartBurst = true
                    }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onToggleLike()
                    Task {
                        try? await Task.sleep(for: .milliseconds(650))
                        withAnimation(.easeOut(duration: 0.25)) {
                            showHeartBurst = false
                        }
                    }
                case .second:
                    togglePlayback()
                }
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
        player?.isMuted = isMuted
        loadState = .loading
        observeItem(of: bound)
        installTimeObserver(on: bound)
        syncPlayback()
    }

    private func unbindPlayer() {
        removeTimeObserver()
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
            }
        }

        failureToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak bound] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            loadState = .failed(error?.localizedDescription ?? "เล่นวิดีโอไม่สำเร็จ")
            bound?.pause()
        }
    }

    private func installTimeObserver(on bound: AVPlayer) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeToken = bound.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let duration = bound.currentItem?.duration.seconds ?? 0
            guard duration.isFinite, duration > 0 else { return }
            let value = time.seconds / duration
            progress = value.isFinite ? min(max(value, 0), 1) : 0
        }
    }

    private func removeTimeObserver() {
        if let timeToken, let bound = player {
            bound.removeTimeObserver(timeToken)
        }
        timeToken = nil
    }

    private func retry() {
        unbindPlayer()
        pool.invalidate(post)
        loadState = .loading
        progress = 0
        isUserPaused = false
        bindPlayer()
    }
}

#Preview {
    VideoPostView(
        post: VideoPost.samples[0],
        isActive: true,
        pool: PlayerPool(),
        onToggleLike: {},
        onToggleSave: {}
    )
    .ignoresSafeArea()
}
