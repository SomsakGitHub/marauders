//
//  VideoFeedView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import SwiftUI

struct VideoFeedView: View {
    @State private var store = FeedStore()
    @State private var pool = PlayerPool()
    @State private var currentID: String?
    @State private var isMuted = false

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
                feed
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
        .onChange(of: isMuted) { _, muted in
            pool.setMuted(muted)
        }
        .sensoryFeedback(.selection, trigger: currentID)
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(store.posts) { post in
                    VideoPostView(
                        post: post,
                        isActive: post.id == currentID,
                        isMuted: isMuted,
                        pool: pool,
                        onToggleMute: { isMuted.toggle() }
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
            pool.setMuted(isMuted)
            if currentID == nil {
                currentID = store.posts.first?.id
            }
            syncPlaybackWindow()
        }
        .onDisappear {
            AudioSessionController.shared.deactivate()
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
        .padding(.bottom, 92)
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
}

#Preview {
    VideoFeedView()
}
