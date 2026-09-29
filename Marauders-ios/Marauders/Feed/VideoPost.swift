//
//  VideoPost.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import Foundation

struct PostAuthor: Identifiable, Hashable, Codable {
    let id: String
    let handle: String
    let displayName: String
    let emoji: String
    let isVerified: Bool
}

struct VideoPost: Identifiable, Hashable, Codable {
    let id: String
    let videoURL: URL
    let author: PostAuthor
    let caption: String
    let music: String
    var likes: Int
    var comments: Int
    var saves: Int
    var shares: Int
    var isLiked: Bool = false
    var isSaved: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case videoURL = "videoUrl"
        case author
        case caption
        case music
        case likes
        case comments
        case saves
        case shares
        case isLiked
        case isSaved
    }
}

extension Int {
    var compact: String {
        formatted(.number.notation(.compactName))
    }
}

extension VideoPost {
    static let samples: [VideoPost] = [
        VideoPost(
            id: "hogsmeade",
            videoURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
            author: PostAuthor(
                id: "dumbledore",
                handle: "@dumbledore",
                displayName: "Albus",
                emoji: "🧙",
                isVerified: true
            ),
            caption: "ยินดีต้อนรับสู่ห้องรวมเพื่อน มาเล่นฟีดคลิปสั้นกันเถอะ 🧹",
            music: "Hedwig's Theme - John Williams",
            likes: 128_400,
            comments: 2_310,
            saves: 9_820,
            shares: 1_204
        ),
        VideoPost(
            id: "quidditch",
            videoURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8")!,
            author: PostAuthor(
                id: "mcgonagall",
                handle: "@mcgonagall",
                displayName: "Minerva",
                emoji: "🐱",
                isVerified: true
            ),
            caption: "ซ้อนควิดดิชนีครั้งที่ 12 ใครซ้อนเป็นบอกบิ๊ก",
            music: "Quidditch March - choir cover",
            likes: 45_900,
            comments: 812,
            saves: 3_004,
            shares: 640
        ),
        VideoPost(
            id: "hogsmeade-night",
            videoURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!,
            author: PostAuthor(
                id: "snape",
                handle: "@snape",
                displayName: "Severus",
                emoji: "🧛",
                isVerified: false
            ),
            caption: "เดินคนเดียวในฮอกส์เมียดตอนกลางคืน... เสียงอะไรนั้นคืออะไร 🔪",
            music: "original sound - the.snape",
            likes: 87_250,
            comments: 5_640,
            saves: 12_480,
            shares: 3_410
        ),
        VideoPost(
            id: "common-room",
            videoURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!,
            author: PostAuthor(
                id: "hermione",
                handle: "@hermione",
                displayName: "Hermione",
                emoji: "📚",
                isVerified: true
            ),
            caption: "อ่านหนังสือ 420 เล่มจบใน 7 วัน 📖 challenge accepted",
            music: "Librarian Vibes - lofi",
            likes: 231_000,
            comments: 12_050,
            saves: 41_300,
            shares: 18_920
        ),
        VideoPost(
            id: "diagon-alley",
            videoURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8")!,
            author: PostAuthor(
                id: "harry",
                handle: "@harry",
                displayName: "Harry",
                emoji: "⚡",
                isVerified: true
            ),
            caption: "เดินซื้อของที่ไดแอกอนอลลีย์ครั้งแรกกันเถอะ 🪄",
            music: "Diagon Alley - ambient",
            likes: 512_800,
            comments: 24_710,
            saves: 63_120,
            shares: 41_050
        )
    ]
}
