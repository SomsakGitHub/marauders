//
//  ContentView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 24/8/2569 BE.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            VideoFeedView()
                .tabItem {
                    Label("Home", systemImage: "play.rectangle.fill")
                }

            MapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
