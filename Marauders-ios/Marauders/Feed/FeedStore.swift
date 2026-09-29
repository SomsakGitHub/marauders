//
//  FeedStore.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import Foundation
import Observation

@Observable
final class FeedStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var posts: [VideoPost] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var actionError: String?

    @ObservationIgnored private let client: FeedAPIClient
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(client: FeedAPIClient = .live, pageSize: Int = AppConfig.feedPageSize) {
        self.client = client
        self.pageSize = pageSize
    }

    deinit {
        loadTask?.cancel()
    }

    @discardableResult
    func loadInitial() -> Task<Void, Never> {
        if let loadTask {
            return loadTask
        }

        phase = .loading
        nextCursor = nil
        hasMore = true

        let task = Task { [weak self] in
            guard let self else { return }
            defer { loadTask = nil }

            do {
                let page = try await client.fetchFeed(cursor: nil, limit: pageSize)
                guard !Task.isCancelled else { return }
                posts = page.items
                nextCursor = page.nextCursor
                hasMore = page.nextCursor != nil
                phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                posts = []
                hasMore = false
                phase = .failed(error.localizedDescription)
            }
        }

        loadTask = task
        return task
    }

    func loadMore(after postID: String?) async {
        guard hasMore, !isLoadingMore, let postID else { return }
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard index >= posts.count - 3 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.fetchFeed(cursor: nextCursor, limit: pageSize)
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    func retry() {
        loadTask?.cancel()
        loadTask = nil
        loadInitial()
    }

    func toggleLike(_ postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        await setLiked(!posts[index].isLiked, postID: postID)
    }

    func like(_ postID: String) async {
        await setLiked(true, postID: postID)
    }

    func setLiked(_ desired: Bool, postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard posts[index].isLiked != desired else { return }

        let previous = posts[index]
        posts[index].isLiked = desired
        posts[index].likes += desired ? 1 : -1

        do {
            apply(try await client.setLiked(desired, postId: postID))
        } catch {
            restore(previous)
            actionError = error.localizedDescription
        }
    }

    func toggleSave(_ postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        await setSaved(!posts[index].isSaved, postID: postID)
    }

    func setSaved(_ desired: Bool, postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard posts[index].isSaved != desired else { return }

        let previous = posts[index]
        posts[index].isSaved = desired
        posts[index].saves += desired ? 1 : -1

        do {
            apply(try await client.setSaved(desired, postId: postID))
        } catch {
            restore(previous)
            actionError = error.localizedDescription
        }
    }

    func dismissActionError() {
        actionError = nil
    }

    private func apply(_ result: ReactionResult) {
        guard let index = posts.firstIndex(where: { $0.id == result.id }) else { return }
        posts[index].likes = result.likes
        posts[index].saves = result.saves
        posts[index].isLiked = result.isLiked
        posts[index].isSaved = result.isSaved
    }

    private func restore(_ post: VideoPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
    }
}
