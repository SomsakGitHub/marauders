//
//  FeedAPIClient.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import Foundation

enum AppConfig {
    static let apiBaseURL = URL(string: "https://marauders-api.js6ctz7gtj.workers.dev")!
    static let feedPageSize = 5

    /// Shared secret the Worker requires on the two write endpoints.
    ///
    /// Read from the bundle rather than written inline so it can be swapped without touching
    /// code, and so it is obvious in a diff when it changes. A token inside the app is not a
    /// secret in the cryptographic sense, anyone who unzips the binary can read it; what it buys
    /// is that the Worker URL alone no longer lets a stranger fill the bucket.
    static let uploadToken: String = {
        Bundle.main.object(forInfoDictionaryKey: "MaraudersUploadToken") as? String ?? ""
    }()
}

enum ViewerIdentity {
    private static let key = "marauders.viewerId"

    static let current: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }()
}

struct FeedPage: Decodable {
    let items: [VideoPost]
    let nextCursor: String?
}

struct ReactionResult: Decodable {
    let id: String
    let likes: Int
    let saves: Int
    let isLiked: Bool
    let isSaved: Bool
}

struct UploadedVideo: Decodable {
    let key: String
    /// A path relative to the API host, resolved against `baseURL` before it is sent to the
    /// player so the bucket itself never has to be public.
    let url: String
    let size: Int
}

enum FeedAPIError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "เซิร์ฟเวอร์ส่งกลับมาในรูปแบบที่อ่านไม่ได้"
        case .server(_, let message):
            message
        case .decoding:
            "ข้อมูลที่ได้รับไม่ตรงกับที่แอปคาดไว้"
        case .transport(let error):
            error.localizedDescription
        }
    }
}

struct FeedAPIClient {
    private struct ErrorBody: Decodable {
        let error: String
    }

    let baseURL: URL
    let viewerId: String
    var uploadToken: String = AppConfig.uploadToken
    var session: URLSession = .shared

    static let live = FeedAPIClient(baseURL: AppConfig.apiBaseURL, viewerId: ViewerIdentity.current)

    func fetchFeed(cursor: String?, limit: Int) async throws -> FeedPage {
        var components = URLComponents(
            url: baseURL.appending(path: "api/feed"),
            resolvingAgainstBaseURL: false
        )
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw FeedAPIError.invalidResponse
        }

        let data = try await send(URLRequest(url: url))
        do {
            return try JSONDecoder().decode(FeedPage.self, from: data)
        } catch {
            throw FeedAPIError.decoding(error)
        }
    }

    func setLiked(_ liked: Bool, postId: String) async throws -> ReactionResult {
        try await setReaction("like", enabled: liked, postId: postId)
    }

    func setSaved(_ saved: Bool, postId: String) async throws -> ReactionResult {
        try await setReaction("save", enabled: saved, postId: postId)
    }

    func uploadVideo(at fileURL: URL, filename: String, contentType: String) async throws -> UploadedVideo {
        let url = baseURL.appending(path: "api/videos")
        let boundary = "marauders-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = MultipartBody(boundary: boundary)
        try body.addFile(at: fileURL, fieldName: "video", filename: filename, contentType: contentType)
        body.finalize()

        let data = try await sendUpload(request, from: body.data)
        do {
            return try JSONDecoder().decode(UploadedVideo.self, from: data)
        } catch {
            throw FeedAPIError.decoding(error)
        }
    }

    func createPost(videoURL: URL, caption: String) async throws -> VideoPost {
        let url = baseURL.appending(path: "api/posts")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "videoUrl": videoURL.absoluteString,
            "caption": caption,
        ])

        let data = try await sendWrite(request)
        do {
            return try JSONDecoder().decode(VideoPost.self, from: data)
        } catch {
            throw FeedAPIError.decoding(error)
        }
    }

    private func setReaction(
        _ name: String,
        enabled: Bool,
        postId: String
    ) async throws -> ReactionResult {
        let url = baseURL
            .appending(path: "api/posts")
            .appending(path: postId)
            .appending(path: name)

        var request = URLRequest(url: url)
        request.httpMethod = enabled ? "POST" : "DELETE"

        let data = try await send(request)
        do {
            return try JSONDecoder().decode(ReactionResult.self, from: data)
        } catch {
            throw FeedAPIError.decoding(error)
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(viewerId, forHTTPHeaderField: "X-Viewer-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            return try await perform(request) { try await session.data(for: $0) }
        } catch let error as FeedAPIError {
            throw error
        } catch {
            throw FeedAPIError.transport(error)
        }
    }

    /// Adds the shared secret on top of the headers every request carries.
    ///
    /// Only the write routes go through this. Reads stay unauthenticated so the feed keeps working
    /// for anyone holding the URL, which is the point of it being a feed.
    private func sendWrite(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(uploadToken, forHTTPHeaderField: "X-Upload-Token")
        return try await send(request)
    }

    /// Uploads go out as a file body rather than through `sendWrite`, so the status handling is
    /// shared but the transport is not.
    private func sendUpload(_ request: URLRequest, from body: Data) async throws -> Data {
        var request = request
        request.setValue(viewerId, forHTTPHeaderField: "X-Viewer-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(uploadToken, forHTTPHeaderField: "X-Upload-Token")

        do {
            return try await perform(request) { try await session.upload(for: $0, from: body) }
        } catch let error as FeedAPIError {
            throw error
        } catch {
            throw FeedAPIError.transport(error)
        }
    }

    private func perform(
        _ request: URLRequest,
        using transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> Data {
        let (data, response) = try await transport(request)

        guard let http = response as? HTTPURLResponse else {
            throw FeedAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "HTTP \(http.statusCode)"
            throw FeedAPIError.server(status: http.statusCode, message: message)
        }
        return data
    }
}
