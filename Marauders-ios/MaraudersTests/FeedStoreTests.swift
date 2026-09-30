//
//  FeedStoreTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import Foundation
import Testing
@testable import Marauders

final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int
        var json: String
    }

    nonisolated(unsafe) static var responder: ((URLRequest) throws -> Response)?
    nonisolated(unsafe) static var recordedPaths: [String] = []
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset() {
        responder = nil
        recordedPaths = []
        recordedRequests = []
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func makeClient(responder: @escaping (URLRequest) throws -> Response) -> FeedAPIClient {
        reset()
        self.responder = responder
        return FeedAPIClient(baseURL: AppConfig.apiBaseURL, viewerId: "test-viewer", session: session())
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.recordedRequests.append(request)
        Self.recordedPaths.append(request.url?.path ?? "")
        Self.recordedPaths.append(request.url?.query ?? "")

        do {
            let response = try Self.responder?(request)
                ?? Response(status: 500, json: #"{"error":"no_stub"}"#)
            let data = Data(response.json.utf8)
            let url = request.url ?? AppConfig.apiBaseURL

            let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func postJSON(id: String, likes: Int, isLiked: Bool = false) -> String {
    """
    {
      "id": "\(id)",
      "videoUrl": "https://example.invalid/\(id).m3u8",
      "author": {
        "id": "\(id)-author",
        "handle": "@\(id)",
        "displayName": "\(id)",
        "emoji": "⚡",
        "isVerified": false
      },
      "caption": "caption-\(id)",
      "music": "original sound",
      "likes": \(likes),
      "comments": 0,
      "saves": 0,
      "shares": 0,
      "isLiked": \(isLiked),
      "isSaved": false
    }
    """
}

private func pageJSON(ids: [String], likes: Int = 10, nextCursor: String?) -> String {
    let items = ids.map { postJSON(id: $0, likes: likes) }.joined(separator: ",")
    let cursor = nextCursor.map { "\"nextCursor\": \"\($0)\"," } ?? "\"nextCursor\": null,"
    return "{ \"items\": [\(items)], \(cursor) \"hasMore\": true }"
}

/// Writes a throwaway clip so the upload path can be exercised without the photo library.
private func makeTemporaryClip(bytes: Data) -> URL? {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "marauders-test-\(UUID().uuidString).mp4")
    do {
        try bytes.write(to: url)
        return url
    } catch {
        return nil
    }
}

@Suite(.serialized)
@MainActor
struct FeedStoreTests {

    @Test("initial load fills the feed and reports another page")
    func initialLoad() async throws {
        let client = StubURLProtocol.makeClient { _ in
            StubURLProtocol.Response(
                status: 200,
                json: pageJSON(ids: ["a", "b"], nextCursor: "cursor-1")
            )
        }
        let store = FeedStore(client: client, pageSize: 2)

        await store.loadInitial().value

        #expect(store.posts.map(\.id) == ["a", "b"])
        #expect(store.phase == .loaded)
        #expect(store.hasMore)
        #expect(store.posts.first?.videoURL.absoluteString == "https://example.invalid/a.m3u8")
    }

    @Test("reaching the tail appends the next page and clears hasMore")
    func loadMoreAppends() async throws {
        let client = StubURLProtocol.makeClient { request in
            let isFirstPage = request.url?.query?.contains("cursor") == false
            if isFirstPage {
                return .init(status: 200, json: pageJSON(ids: ["a", "b"], nextCursor: "cursor-1"))
            }
            return .init(status: 200, json: pageJSON(ids: ["c", "d"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 2)

        await store.loadInitial().value
        await store.loadMore(after: "b")

        #expect(store.posts.map(\.id) == ["a", "b", "c", "d"])
        #expect(store.hasMore == false)
    }

    @Test("scrolling short of the tail does not request another page")
    func loadMoreSkipsWhenNotAtTail() async throws {
        let client = StubURLProtocol.makeClient { _ in
            StubURLProtocol.Response(
                status: 200,
                json: pageJSON(ids: ["a", "b", "c", "d", "e"], nextCursor: "cursor-1")
            )
        }
        let store = FeedStore(client: client, pageSize: 5)

        await store.loadInitial().value
        let before = StubURLProtocol.recordedPaths.filter { $0.hasPrefix("cursor=") }.count
        await store.loadMore(after: "a")
        let after = StubURLProtocol.recordedPaths.filter { $0.hasPrefix("cursor=") }.count

        #expect(before == after)
        #expect(store.posts.count == 5)
    }

    @Test("a failing feed surfaces the error and stays retryable")
    func initialLoadFailure() async throws {
        let client = StubURLProtocol.makeClient { _ in
            throw URLError(.notConnectedToInternet)
        }
        let store = FeedStore(client: client, pageSize: 2)

        await store.loadInitial().value

        #expect(store.posts.isEmpty)
        guard case .failed = store.phase else {
            Issue.record("expected a failed phase, got \(store.phase)")
            return
        }

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Response(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let retrying = FeedStore(client: client, pageSize: 2)
        await retrying.loadInitial().value
        #expect(retrying.phase == .loaded)
        #expect(retrying.posts.map(\.id) == ["a"])
    }

    @Test("like applies optimistically then reconciles with the server count")
    func optimisticLike() async throws {
        let client = StubURLProtocol.makeClient { request in
            if request.url?.path.hasSuffix("/like") == true {
                return .init(
                    status: 200,
                    json: #"{"id":"a","likes":11,"saves":0,"isLiked":true,"isSaved":false}"#
                )
            }
            return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 1)

        await store.loadInitial().value
        #expect(store.posts[0].isLiked == false)

        await store.toggleLike("a")

        #expect(store.posts[0].isLiked)
        #expect(store.posts[0].likes == 11)
        #expect(store.actionError == nil)
        #expect(StubURLProtocol.recordedPaths.contains("/api/posts/a/like"))
    }

    @Test("a rejected like rolls the optimistic change back")
    func likeRollsBackOnFailure() async throws {
        let client = StubURLProtocol.makeClient { request in
            if request.url?.path.hasSuffix("/like") == true {
                return .init(status: 500, json: #"{"error":"internal_error"}"#)
            }
            return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 1)

        await store.loadInitial().value
        await store.toggleLike("a")

        #expect(store.posts[0].isLiked == false)
        #expect(store.posts[0].likes == 10)
        #expect(store.actionError != nil)

        store.dismissActionError()
        #expect(store.actionError == nil)
    }

    @Test("double tap likes without ever unliking, and skips the request when already liked")
    func likeIsNotAToggle() async throws {
        let client = StubURLProtocol.makeClient { request in
            if request.url?.path.hasSuffix("/like") == true {
                return .init(
                    status: 200,
                    json: #"{"id":"a","likes":11,"saves":0,"isLiked":true,"isSaved":false}"#
                )
            }
            return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 1)

        await store.loadInitial().value
        await store.like("a")
        await store.like("a")
        await store.like("a")

        #expect(store.posts[0].isLiked)
        #expect(store.posts[0].likes == 11)

        let likeRequests = StubURLProtocol.recordedPaths.filter { $0 == "/api/posts/a/like" }
        #expect(likeRequests.count == 1)
    }

    @Test("publishing a clip uploads it, creates the post, and puts it on top")
    func publishPutsNewPostFirst() async throws {
        let clipURL = try #require(makeTemporaryClip(bytes: Data([0x00, 0x01, 0x02])))
        defer { try? FileManager.default.removeItem(at: clipURL) }

        let client = StubURLProtocol.makeClient { request in
            switch request.url?.path {
            case "/api/videos":
                return .init(
                    status: 201,
                    json: #"{"key":"videos/abc.mp4","url":"/api/videos/abc.mp4","size":3}"#
                )
            case "/api/posts":
                return .init(
                    status: 201,
                    json: postJSON(id: "new-post", likes: 0)
                        .replacingOccurrences(
                            of: "https://example.invalid/new-post.m3u8",
                            with: "https://marauders-api.js6ctz7gtj.workers.dev/api/videos/abc.mp4"
                        )
                )
            default:
                return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
            }
        }
        let store = FeedStore(client: client, pageSize: 1)
        await store.loadInitial().value

        let newID = await store.publish(
            clipURL: clipURL,
            filename: "clip.mp4",
            contentType: "video/mp4",
            caption: ""
        )

        #expect(newID == "new-post")
        #expect(store.posts.map(\.id) == ["new-post", "a"])
        #expect(store.phase == .loaded)
        #expect(store.actionError == nil)

        // The relative path from the upload response is resolved before the post is created,
        // otherwise the API would reject it.
        #expect(StubURLProtocol.recordedPaths.contains("/api/videos"))
        #expect(StubURLProtocol.recordedPaths.contains("/api/posts"))
    }

    @Test("a rejected upload reports the error and leaves the feed alone")
    func publishFailureKeepsFeed() async throws {
        let clipURL = try #require(makeTemporaryClip(bytes: Data([0x00])))
        defer { try? FileManager.default.removeItem(at: clipURL) }

        let client = StubURLProtocol.makeClient { request in
            if request.url?.path == "/api/videos" {
                return .init(status: 413, json: #"{"error":"video_too_large"}"#)
            }
            return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 1)
        await store.loadInitial().value

        let newID = await store.publish(
            clipURL: clipURL,
            filename: "clip.mp4",
            contentType: "video/mp4",
            caption: ""
        )

        #expect(newID == nil)
        #expect(store.posts.map(\.id) == ["a"])
        #expect(store.actionError == "video_too_large")
        #expect(store.uploadState == .idle)
    }

    @Test("an empty feed loads without inventing a post")
    func emptyFeedIsLoadedNotFailed() async throws {
        let client = StubURLProtocol.makeClient { _ in
            StubURLProtocol.Response(status: 200, json: #"{ "items": [], "nextCursor": null }"#)
        }
        let store = FeedStore(client: client, pageSize: 2)

        await store.loadInitial().value

        #expect(store.phase == .loaded)
        #expect(store.posts.isEmpty)
        #expect(store.hasMore == false)
        #expect(store.actionError == nil)
    }

    @Test("publishing into an empty feed is the first and only post")
    func publishIntoEmptyFeed() async throws {
        let clipURL = try #require(makeTemporaryClip(bytes: Data([0x00, 0x01])))
        defer { try? FileManager.default.removeItem(at: clipURL) }

        let client = StubURLProtocol.makeClient { request in
            switch request.url?.path {
            case "/api/videos":
                return .init(
                    status: 201,
                    json: #"{"key":"videos/first.mp4","url":"/api/videos/first.mp4","size":2}"#
                )
            case "/api/posts":
                return .init(status: 201, json: postJSON(id: "first", likes: 0))
            default:
                return .init(status: 200, json: #"{ "items": [], "nextCursor": null }"#)
            }
        }
        let store = FeedStore(client: client, pageSize: 2)
        await store.loadInitial().value

        let newID = await store.publish(
            clipURL: clipURL,
            filename: "clip.mp4",
            contentType: "video/mp4",
            caption: ""
        )

        #expect(newID == "first")
        #expect(store.posts.map(\.id) == ["first"])
        #expect(store.phase == .loaded)
    }

    @Test("the rail button still toggles a like off")
    func toggleUnlikeStillWorks() async throws {
        let client = StubURLProtocol.makeClient { request in
            if request.url?.path.hasSuffix("/like") == true {
                return .init(
                    status: 200,
                    json: #"{"id":"a","likes":9,"saves":0,"isLiked":false,"isSaved":false}"#
                )
            }
            return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        let store = FeedStore(client: client, pageSize: 1)

        await store.loadInitial().value
        await store.like("a")
        await store.toggleLike("a")

        #expect(store.posts[0].isLiked == false)
        #expect(store.posts[0].likes == 9)
    }

    @Test("the write routes carry the upload token")
    func writeRequestsCarryToken() async throws {
        let clipURL = try #require(makeTemporaryClip(bytes: Data([0x00, 0x01])))
        defer { try? FileManager.default.removeItem(at: clipURL) }

        let client = StubURLProtocol.makeClient { request in
            switch request.url?.path {
            case "/api/videos":
                return .init(
                    status: 201,
                    json: #"{"key":"videos/tok.mp4","url":"/api/videos/tok.mp4","size":2}"#
                )
            case "/api/posts":
                return .init(status: 201, json: postJSON(id: "tok", likes: 0))
            default:
                return .init(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
            }
        }
        var withToken = client
        withToken.uploadToken = "secret-token"
        let store = FeedStore(client: withToken, pageSize: 1)
        await store.loadInitial().value

        _ = await store.publish(
            clipURL: clipURL,
            filename: "clip.mp4",
            contentType: "video/mp4",
            caption: ""
        )

        let upload = StubURLProtocol.recordedRequests.filter { $0.url?.path == "/api/videos" }
        let create = StubURLProtocol.recordedRequests.filter { $0.url?.path == "/api/posts" }
        #expect(upload.count == 1)
        #expect(create.count == 1)
        #expect(upload.first?.value(forHTTPHeaderField: "X-Upload-Token") == "secret-token")
        #expect(create.first?.value(forHTTPHeaderField: "X-Upload-Token") == "secret-token")
    }

    @Test("reads stay unauthenticated, so the feed keeps working without the token")
    func readRequestsOmitToken() async throws {
        let client = StubURLProtocol.makeClient { _ in
            StubURLProtocol.Response(status: 200, json: pageJSON(ids: ["a"], nextCursor: nil))
        }
        var withToken = client
        withToken.uploadToken = "secret-token"
        let store = FeedStore(client: withToken, pageSize: 1)

        await store.loadInitial().value

        let feed = StubURLProtocol.recordedRequests.filter { $0.url?.path == "/api/feed" }
        #expect(feed.count == 1)
        #expect(feed.first?.value(forHTTPHeaderField: "X-Upload-Token") == nil)
        // The viewer id is still sent, since reactions are keyed off it.
        #expect(feed.first?.value(forHTTPHeaderField: "X-Viewer-Id") == "test-viewer")
    }
}
