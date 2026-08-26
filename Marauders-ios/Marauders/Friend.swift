//
//  Friend.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 25/8/2569 BE.
//

import Foundation
import CoreLocation

struct Friend: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Friend {
    static let samples: [Friend] = [
        Friend(name: "สมชาย", emoji: "🧙", latitude: 13.7563, longitude: 100.5018),
        Friend(name: "สมหญิง", emoji: "🧹", latitude: 13.7445, longitude: 100.5327),
        Friend(name: "วิชัย", emoji: "⚡", latitude: 13.7462, longitude: 100.5010),
        Friend(name: "นารี", emoji: "🦉", latitude: 13.7595, longitude: 100.4983),
        Friend(name: "ประเสริฐ", emoji: "🏰", latitude: 13.7510, longitude: 100.5240),
    ]
}
