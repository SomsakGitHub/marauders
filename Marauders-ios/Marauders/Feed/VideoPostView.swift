//
//  VideoPostView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import SwiftUI

struct VideoPostView: View {
    let post: VideoPost
    let isActive: Bool
    let pool: PlayerPool
    let onToggleLike: () -> Void
    let onToggleSave: () -> Void

    @State private var isMuted = false
    @State private var isUserPaused = false
    @State private var showHeartBurst = false
    @State private var isDiscSpinning = false
    @State private var progress: Double = 0
    @State private var timeToken: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = pool.player(for: post) {
                VideoPlayerSurface(player: player)
                    .ignoresSafeArea()
            }

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
                    .id("heart-burst")
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
            installTimeObserver()
        }
        .onDisappear {
            removeTimeObserver()
        }
        .onChange(of: isActive) { _, active in
            guard let player = pool.player(for: post) else { return }
            if active {
                if !isUserPaused { player.play() }
            } else {
                player.pause()
                player.seek(to: .zero)
                progress = 0
            }
        }
        .onChange(of: isMuted) { _, muted in
            pool.cachedPlayer(for: post.videoURL)?.isMuted = muted
        }
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
        guard isActive, let player = pool.player(for: post) else { return }
        isUserPaused.toggle()
        if isUserPaused {
            player.pause()
        } else {
            player.play()
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func installTimeObserver() {
        guard timeToken == nil, let player = pool.player(for: post) else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let duration = player.currentItem?.duration.seconds ?? 0
            guard duration.isFinite, duration > 0 else { return }
            let value = time.seconds / duration
            progress = value.isFinite ? min(max(value, 0), 1) : 0
        }
    }

    private func removeTimeObserver() {
        guard let timeToken, let player = pool.cachedPlayer(for: post.videoURL) else { return }
        player.removeTimeObserver(timeToken)
        self.timeToken = nil
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
