//
//  VideoFeedView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import SwiftUI

struct VideoFeedView: View {
    @State private var pool = PlayerPool()
    @State private var posts = VideoPost.samples
    @State private var currentID: String?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    VideoPostView(
                        post: post,
                        isActive: post.id == currentID,
                        pool: pool,
                        onToggleLike: { toggleLike(post.id) },
                        onToggleSave: { toggleSave(post.id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerRelativeFrame(.vertical)
                    .id(post.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentID, anchor: .top)
        .ignoresSafeArea()
        .background(.black)
        .onAppear {
            currentID = currentID ?? posts.first?.id
            warmNeighbourhood(of: currentID)
        }
        .onChange(of: currentID) { _, id in
            pool.pauseAll(except: id.flatMap(lookupURL))
            warmNeighbourhood(of: id)
        }
    }

    private func lookupURL(_ id: String?) -> URL? {
        guard let id else { return nil }
        return posts.first { $0.id == id }?.videoURL
    }

    private func warmNeighbourhood(of id: String?) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        let lower = max(index - 1, 0)
        let upper = min(index + 1, posts.count - 1)
        let window = Array(posts[lower...upper])
        pool.keepAlive(window)
        for post in window {
            _ = pool.player(for: post)
        }
    }

    private func toggleLike(_ id: String) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].isLiked.toggle()
        posts[index].likes += posts[index].isLiked ? 1 : -1
    }

    private func toggleSave(_ id: String) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].isSaved.toggle()
        posts[index].saves += posts[index].isSaved ? 1 : -1
    }
}

#Preview {
    VideoFeedView()
}
