//
//  MultipartBodyTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import Foundation
import Testing
@testable import Marauders

@Suite
struct MultipartBodyTests {

    @Test("the file part carries the field name, filename, and content type")
    func buildsFilePart() throws {
        var body = MultipartBody(boundary: "BOUND")
        body.addFile(data: Data("clip".utf8), fieldName: "video", filename: "clip.mp4", contentType: "video/mp4")
        body.finalize()

        let text = try #require(String(data: body.data, encoding: .utf8))
        #expect(text == """
        --BOUND\r
        Content-Disposition: form-data; name="video"; filename="clip.mp4"\r
        Content-Type: video/mp4\r
        \r
        clip\r
        --BOUND--\r

        """)
    }

    @Test("a filename that could forge a delimiter is neutralised")
    func escapesFilename() throws {
        var body = MultipartBody(boundary: "BOUND")
        body.addFile(data: Data(), fieldName: "video", filename: "a\"\r\n--BOUND\r\nx", contentType: "video/mp4")
        body.finalize()

        let text = try #require(String(data: body.data, encoding: .utf8))
        let parts = text.components(separatedBy: "--BOUND\r\n")
        #expect(parts.count == 2)
        #expect(text.contains(#"filename="a___--BOUND__x""#))
    }

    @Test("bytes are written unchanged between the headers and the closing delimiter")
    func keepsBinaryIntact() throws {
        // Deliberately not valid UTF-8, so a text round trip would corrupt it.
        let bytes = Data([0x00, 0xFF, 0x1A, 0x0A, 0x0D])
        var body = MultipartBody(boundary: "B")
        body.addFile(data: bytes, fieldName: "video", filename: "c.mp4", contentType: "video/mp4")
        body.finalize()

        let marker = Data("Content-Type: video/mp4\r\n\r\n".utf8)
        let start = try #require(body.data.range(of: marker)?.upperBound)
        let end = body.data.count - Data("\r\n--B--\r\n".utf8).count
        #expect(Data(body.data[start..<end]) == bytes)
    }

    @Test("reading a clip from disk sends the same bytes")
    func readsFromFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "marauders-multipart-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data([0x01, 0x02, 0x03])
        try bytes.write(to: url)

        var body = MultipartBody(boundary: "B")
        try body.addFile(at: url, fieldName: "video", filename: "c.mp4", contentType: "video/mp4")
        body.finalize()

        let marker = Data("Content-Type: video/mp4\r\n\r\n".utf8)
        let start = try #require(body.data.range(of: marker)?.upperBound)
        let end = body.data.count - Data("\r\n--B--\r\n".utf8).count
        #expect(Data(body.data[start..<end]) == bytes)
    }
}
