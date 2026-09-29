//
//  VideoFeedView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import SwiftUI

struct VideoFeedView: View {
    /// Owned by `ContentView` so the upload tab publishes into the same feed.
    let store: FeedStore
    /// Set when a post is published from another tab, which scrolls the feed to it.
    @Binding var focusPostID: String?

    @State private var pool = PlayerPool()
    @State private var currentID: String?
    @State private var failedIDs: Set<String> = []
    @State private var isExhausted = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch store.phase {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

            case .failed(let message):
                feedErrorCard(message)

            case .loaded:
                loadedFeed
            }

            if isExhausted, store.phase == .loaded {
                exhaustedCard
            }

            if let message = store.actionError {
                actionErrorToast(message)
            }
        }
        .task {
            if case .idle = store.phase {
                store.loadInitial()
            }
        }
        .onChange(of: currentID) { _, id in
            syncPlaybackWindow()
            Task { await store.loadMore(after: id) }
        }
        .onChange(of: focusPostID) { _, id in
            guard let id else { return }
            failedIDs.remove(id)
            isExhausted = false
            currentID = id
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .loaded {
                failedIDs = []
                isExhausted = false
            }
        }
        .sensoryFeedback(.selection, trigger: currentID)
    }

    @ViewBuilder
    private var loadedFeed: some View {
        if store.posts.isEmpty {
            emptyFeedCard
        } else {
            feed
        }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(store.posts) { post in
                    VideoPostView(
                        post: post,
                        isActive: post.id == currentID,
                        pool: pool,
                        onLoadFailed: { handleLoadFailure(of: post.id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerRelativeFrame(.vertical)
                    .id(post.id)
                }
            }
            .scrollTargetLayout()

            if !store.hasMore, !store.posts.isEmpty {
                endOfFeedMarker
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentID, anchor: .top)
        .ignoresSafeArea()
        .onAppear {
            AudioSessionController.shared.activate()
            if currentID == nil {
                currentID = store.posts.first?.id
            }
            syncPlaybackWindow()
        }
        .onChange(of: scenePhase) { _, phase in
            // The feed outlives the tab bar now, so the app going away is the only thing left that
            // should take the audio session back. Releasing it on tab switches is what used to
            // stop a clip mid sentence.
            switch phase {
            case .active:
                AudioSessionController.shared.activate()
                syncPlaybackWindow()
            case .inactive, .background:
                pool.pauseAll(except: nil)
                AudioSessionController.shared.deactivate()
            @unknown default:
                break
            }
        }
    }

    private var endOfFeedMarker: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.8))
            Text("ดูครบทุกคลิปแล้ว")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.bottom, 96)
    }

    private var exhaustedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.white)

            Text("ไม่มีคลิปที่เล่นได้")
                .font(.headline)
                .foregroundStyle(.white)

            Text("คลิปที่เหลือในฟีดนี้โหลดไม่ผ่าน")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))

            Button {
                failedIDs = []
                isExhausted = false
                store.retry()
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
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 36)
    }

    /// Shown when the feed has no posts at all, which is the state right after the database is
    /// cleared and before the first clip is uploaded.
    private var emptyFeedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.white)

            Text("ยังไม่มีคลิป")
                .font(.headline)
                .foregroundStyle(.white)

            Text("เปิดแท็บ \"เพิ่ม\" เพื่อเลือกวิดีโอจากเครื่องแล้วอัปโหลดคลิปแรก")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 36)
    }

    private func feedErrorCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(.white)

            Text("โหลดฟีดไม่สำเร็จ")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))

            Button {
                store.retry()
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
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 36)
    }

    private func actionErrorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .lineLimit(2)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 120)
            .padding(.horizontal, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: message) {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                store.dismissActionError()
            }
        }
    }

    private func syncPlaybackWindow() {
        guard let index = store.posts.firstIndex(where: { $0.id == currentID }) else { return }

        let lower = max(index - 1, 0)
        let upper = min(index + 1, store.posts.count - 1)
        pool.warm(Array(store.posts[lower...upper]))
        pool.activate(store.posts[index])
    }

    /// A clip that cannot play is skipped rather than shown. Preloaded clips report in ahead of
    /// time, so a failure on an inactive post is only remembered here; the jump happens when it
    /// is the one being watched.
    private func handleLoadFailure(of postID: String) {
        failedIDs.insert(postID)
        guard postID == currentID, !isExhausted else { return }
        skip(after: postID)
    }

    private func skip(after postID: String) {
        if let next = nextPlayable(after: postID) {
            isExhausted = false
            currentID = next
            return
        }

        // The failure landed on the last loaded post, so the page boundary may be hiding more
        // clips. Pull the next page before deciding the feed is done.
        guard store.hasMore else {
            isExhausted = true
            return
        }

        Task {
            await store.loadMore(after: postID)
            if let next = nextPlayable(after: postID) {
                isExhausted = false
                currentID = next
            } else {
                isExhausted = true
            }
        }
    }

    private func nextPlayable(after postID: String) -> String? {
        PlaybackSkipper.next(after: postID, in: store.posts.map(\.id), skipping: failedIDs)
    }
}

#Preview {
    VideoFeedView(store: FeedStore(), focusPostID: .constant(nil))
}
