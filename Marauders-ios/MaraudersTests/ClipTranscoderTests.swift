//
//  ClipTranscoderTests.swift
//  MaraudersTests
//
//  Created by tiscomacnb2486 on 1/10/2569 BE.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Marauders

@Suite("ClipTranscoder")
struct ClipTranscoderTests {

    // MARK: - Target size

    @Test("a portrait clip is left at its own size")
    func portraitIsNotScaled() {
        let size = ClipTranscoder.outputSize(
            naturalSize: CGSize(width: 1080, height: 1920),
            transform: .identity
        )

        #expect(size.width == 1080)
        #expect(size.height == 1920)
    }

    @Test("a rotated landscape clip is measured by its displayed short side")
    func rotationUsesDisplayedShortSide() {
        // The phone stores portrait footage as a 1920x1080 frame turned a quarter turn. It is
        // already at the target width, so it must be passed through untouched.
        let size = ClipTranscoder.outputSize(
            naturalSize: CGSize(width: 1920, height: 1080),
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        )

        #expect(size.width == 1920)
        #expect(size.height == 1080)
    }

    @Test("a landscape clip is capped by its height")
    func landscapeIsCapped() {
        let size = ClipTranscoder.outputSize(
            naturalSize: CGSize(width: 1920, height: 1200),
            transform: .identity
        )

        #expect(size.width == 1728)
        #expect(size.height == 1080)
    }

    @Test("a clip above the ceiling is scaled down")
    func oversizedIsScaledDown() {
        let size = ClipTranscoder.outputSize(
            naturalSize: CGSize(width: 3840, height: 2160),
            transform: .identity
        )

        #expect(size.width == 1920)
        #expect(size.height == 1080)
    }

    @Test("output dimensions are even, as the encoder requires")
    func dimensionsAreEven() {
        let size = ClipTranscoder.outputSize(
            naturalSize: CGSize(width: 1001, height: 1777),
            transform: .identity
        )

        #expect(size.width % 2 == 0)
        #expect(size.height % 2 == 0)
    }

    // MARK: - Audio track selection

    @Test("the plain AAC track is recognised despite its NUL padding")
    func recognisesAAC() {
        // "aac\0" is what a four character code looks like on the wire.
        #expect(ClipTranscoder.isPlainAudio(0x6161_6300))
        #expect(ClipTranscoder.isPlainAudio(0x6D70_3461))
        #expect(ClipTranscoder.fourCCString(0x6161_6300) == "aac")
    }

    @Test("the ambisonic track is not treated as plain audio")
    func rejectsAmbisonic() {
        #expect(ClipTranscoder.isPlainAudio(0x6170_6163) == false)
        #expect(ClipTranscoder.fourCCString(0x6170_6163) == "apac")
    }

    // MARK: - End to end

    @Test("a rotated clip is re-encoded, stays the right way up, and gets its metadata at the front")
    func transcodeRewritesAndFastStarts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "marauders-transcode-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try await makeFixture(
            width: 1920,
            height: 1080,
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
            frames: 15,
            in: directory
        )

        let output = try await ClipTranscoder.transcode(source, to: directory)
        #expect(FileManager.default.fileExists(atPath: output.path))

        let asset = AVURLAsset(url: output)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let duration = try await asset.load(.duration)
        let natural = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let display = natural.applying(transform)

        #expect(try await asset.load(.isPlayable))
        #expect(abs(duration.seconds - 0.5) < 0.1)
        // The quarter turn is carried on the output track, so the displayed frame is portrait
        // even though the encoded frame is landscape.
        #expect(abs(display.width) == 1080)
        #expect(abs(display.height) == 1920)

        let atoms = atomOrder(of: output)
        let moov = try #require(atoms.firstIndex(of: "moov"))
        let mdat = try #require(atoms.firstIndex(of: "mdat"))
        #expect(moov < mdat)
    }

    // MARK: - Helpers

    private func makeFixture(
        width: Int,
        height: Int,
        transform: CGAffineTransform,
        frames: Int,
        in directory: URL
    ) async throws -> URL {
        let url = directory.appending(path: "fixture-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.transform = transform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)

        guard writer.startWriting() else { throw writer.error ?? FixtureError.startFailed }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try makePixelBuffer(width: width, height: height, frame: frame)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? FixtureError.appendFailed
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        return url
    }

    private func makePixelBuffer(width: Int, height: Int, frame: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw FixtureError.pixelBufferFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
            // A moving block makes each frame different, which keeps the encoder from collapsing
            // the clip to almost nothing.
            context?.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context?.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
            context?.fill(CGRect(x: frame * width / 15, y: 0, width: width / 6, height: height))
        }

        return buffer
    }

    private func atomOrder(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
        var order: [String] = []
        var offset = 0

        while offset + 8 <= size {
            try? handle.seek(toOffset: UInt64(offset))
            guard let header = try? handle.read(upToCount: 16), header.count >= 8 else { break }

            var atomSize = (Int(header[0]) << 24) | (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
            let type = String(bytes: header[4..<8], encoding: .ascii) ?? "????"
            if atomSize == 1 {
                var extended = 0
                for byte in header[8..<16] { extended = (extended << 8) | Int(byte) }
                atomSize = extended
            } else if atomSize == 0 {
                atomSize = size - offset
            }
            if atomSize < 8 { break }

            order.append(type)
            offset += atomSize
        }
        return order
    }

    private enum FixtureError: Error {
        case startFailed
        case appendFailed
        case pixelBufferFailed
    }
}
