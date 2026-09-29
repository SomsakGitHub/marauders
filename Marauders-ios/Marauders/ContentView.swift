//
//  ContentView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 24/8/2569 BE.
//

import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case home
        case upload
    }

    @State private var store = FeedStore()
    @State private var selection: Tab = .home
    @State private var focusPostID: String?

    var body: some View {
        TabView(selection: $selection) {
            VideoFeedView(store: store, focusPostID: $focusPostID)
                .tabItem {
                    Label("Home", systemImage: "play.rectangle.fill")
                }
                .tag(Tab.home)

            UploadView(store: store) { newID in
                // Publish into the shared store, then bring the feed forward on the new post.
                focusPostID = newID
                selection = .home
            }
            .tabItem {
                Label("เพิ่ม", systemImage: "plus.circle.fill")
            }
            .tag(Tab.upload)
        }
        .tint(.white)
    }
}

#Preview {
    ContentView()
}
