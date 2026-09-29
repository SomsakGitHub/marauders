//
//  MultipartBody.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation

/// Builds a multipart/form-data body in memory.
///
/// The clip is capped at 64 MB on the server, so a clip sized for a phone feed fits comfortably
/// and avoids the file coordination a streamed body would need.
struct MultipartBody {
    private let boundary: String
    private(set) var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addFile(
        at fileURL: URL,
        fieldName: String,
        filename: String,
        contentType: String
    ) throws {
        let contents = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        addFile(data: contents, fieldName: fieldName, filename: filename, contentType: contentType)
    }

    mutating func addFile(
        data contents: Data,
        fieldName: String,
        filename: String,
        contentType: String
    ) {
        // The filename is echoed back in the boundary block, so anything that could inject a
        // delimiter is escaped rather than written raw.
        let safeName = filename
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")

        data.append(utf8: "--\(boundary)\r\n")
        data.append(
            utf8: "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeName)\"\r\n"
        )
        data.append(utf8: "Content-Type: \(contentType)\r\n\r\n")
        data.append(contents)
        data.append(utf8: "\r\n")
    }

    /// Appends the closing delimiter. Called once all parts are added.
    mutating func finalize() {
        data.append(utf8: "--\(boundary)--\r\n")
    }
}

private extension Data {
    mutating func append(utf8 string: String) {
        append(Data(string.utf8))
    }
}
