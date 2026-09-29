//
//  PickedVideo.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A clip handed over by `PhotosPicker`, already copied somewhere this process owns.
///
/// The photo library's file is temporary and is deleted once the picker call returns, so the
/// bytes are moved during the transfer rather than read back later.
struct PickedVideo: Transferable {
    let url: URL
    let filename: String
    let contentType: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let name = received.file.lastPathComponent
            let staged = FileManager.default.temporaryDirectory
                .appending(path: "marauders-\(UUID().uuidString)-\(name)")

            try FileManager.default.copyItem(at: received.file, to: staged)

            let type = UTType(filenameExtension: staged.pathExtension)
            return PickedVideo(
                url: staged,
                filename: staged.lastPathComponent,
                contentType: type?.preferredMIMEType ?? "video/mp4"
            )
        }
    }
}
