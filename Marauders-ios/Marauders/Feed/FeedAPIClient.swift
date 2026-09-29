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
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw FeedAPIError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                    ?? "HTTP \(http.statusCode)"
                throw FeedAPIError.server(status: http.statusCode, message: message)
            }
            return data
        } catch let error as FeedAPIError {
            throw error
        } catch {
            throw FeedAPIError.transport(error)
        }
    }
}
