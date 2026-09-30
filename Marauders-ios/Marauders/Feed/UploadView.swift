//
//  UploadView.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import PhotosUI
import SwiftUI

/// The second tab: pick a clip off the phone and publish it to the feed.
///
/// Uploading lives here rather than in the feed because the feed owns every `AVPlayer` and a
/// picker plus a progress state would sit awkwardly on top of the paging container. The store
/// is shared, so a published post appears at the top of the feed without a refetch.
struct UploadView: View {
    let store: FeedStore
    let onPublished: (String) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isPreparingClip = false

    private var isBusy: Bool {
        isPreparingClip || store.uploadState != .idle
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: "video.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)

                Text("เพิ่มวิดีโอ")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("เลือกคลิปสั้นจากเครื่อง แล้วจะขึ้นเป็นโพสต์แรกในฟีดทันที")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 40)

                PhotosPicker(
                    selection: $pickerItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(buttonTitle)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.6 : 1)
                .padding(.top, 4)

                if let message = store.actionError {
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 40)
                }

                Spacer()
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await publish(item) }
        }
    }

    private var buttonTitle: String {
        switch (isPreparingClip, store.uploadState) {
        case (true, _):
            "กำลังเตรียมคลิป"
        case (_, .uploading):
            "กำลังอัปโหลด"
        case (_, .posting):
            "กำลังสร้างโพสต์"
        default:
            "เลือกจากเครื่อง"
        }
    }

    /// Copies the picked clip out of the photo library, shrinks it, then uploads the result.
    ///
    /// The library hands back a file that can vanish as soon as the picker call returns, so it
    /// is moved to a path this scope owns. That copy is re-encoded before it goes out, both to
    /// bring the bitrate down to something the feed can stream and to move the file's metadata to
    /// the front. The re-encoded file is a `.mp4` whatever the picker handed over.
    private func publish(_ item: PhotosPickerItem) async {
        isPreparingClip = true
        defer {
            isPreparingClip = false
            pickerItem = nil
        }

        do {
            guard let clip = try await item.loadTransferable(type: PickedVideo.self) else {
                store.report("เลือกคลิปนี้ไม่ได้")
                return
            }
            defer { try? FileManager.default.removeItem(at: clip.url) }

            let optimized = try await ClipTranscoder.transcode(clip.url)
            defer { try? FileManager.default.removeItem(at: optimized) }

            if let newID = await store.publish(
                clipURL: optimized,
                filename: optimized.lastPathComponent,
                contentType: "video/mp4",
                caption: ""
            ) {
                onPublished(newID)
            }
        } catch {
            store.report(error.localizedDescription)
        }
    }
}

#Preview {
    UploadView(store: FeedStore(), onPublished: { _ in })
}
