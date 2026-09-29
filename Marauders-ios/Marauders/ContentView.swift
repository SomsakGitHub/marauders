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

    /// Both tabs stay mounted and only their opacity, hit testing and z order change.
    ///
    /// A `TabView` tears the feed down on every switch, which throws the pooled `AVPlayer` away
    /// and drops the clip back to its first frame when you come back. TikTok keeps the clip
    /// running while you sit on the other tab, and keeping both views alive is what buys that.
    var body: some View {
        ZStack {
            VideoFeedView(
                store: store,
                focusPostID: $focusPostID,
                isVisible: selection == .home
            )

            UploadView(store: store) { newID in
                // Publish into the shared store, then bring the feed forward on the new post.
                focusPostID = newID
                selection = .home
            }
            .opacity(selection == .upload ? 1 : 0)
            .allowsHitTesting(selection == .upload)
            .accessibilityHidden(selection != .upload)
        }
        .overlay(alignment: .bottom) { tabBar }
    }

    /// A scrim instead of an opaque bar. The feed ignores the safe area, so the clip runs behind
    /// the bar and the icons need to carry their own contrast rather than inherit a background.
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home, title: "หน้าแรก", systemImage: "play.rectangle.fill")
            tabButton(.upload, title: "เพิ่ม", systemImage: "plus.circle.fill")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ tab: Tab, title: String, systemImage: String) -> some View {
        Button {
            selection = tab
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection == tab ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
