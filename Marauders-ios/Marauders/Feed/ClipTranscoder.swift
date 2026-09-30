//
//  ClipTranscoder.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 1/10/2569 BE.
//

import AVFoundation
import Foundation
import VideoToolbox

/// Rewrites a picked clip into the shape the feed wants to stream.
///
/// Phone clips arrive far above what the feed can use. A 33 second clip lands around 64 MB, right
/// on the upload ceiling, and its metadata atom sits at the end of the file so a player has to
/// fetch the tail before it can start. This re-encodes the video at a fixed bitrate, drops the
/// ambisonic track the feed has no use for, and lays the metadata out at the front of the file.
///
/// The numbers were measured rather than guessed. On a 32 second 64 MB clip, 6 Mbit/s produces a
/// 25 MB file, 37% of the ceiling, in about four seconds of encode, so a clip would have to run
/// past eighty seconds before size became a problem again.
nonisolated enum ClipTranscoder {
    /// Six megabits is generous for a phone screen at 1080 wide and leaves the largest clips well
    /// inside the ceiling. Raising it mostly buys bitrate the display cannot show.
    static let videoBitrate = 6_000_000
    static let audioBitrate = 128_000
    static let audioSampleRate = 48_000
    static let audioChannels = 2
    /// The feed shows a phone screen, so the short side is the one that has to fit. A clip already
    /// at or below this is passed through at its own size instead of being scaled up.
    static let maxShortSide = 1080

    /// AAC arrives tagged as either code depending on the writer that produced it. The clips the
    /// library hands back use `aac`; the ambisonic track is `apac`.
    static let plainAudioTypes: Set<String> = ["mp4a", "aac"]

    enum Failure: LocalizedError {
        case noVideoTrack
        case setupFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "คลิปนี้ไม่มีวิดีโอให้แปลง"
            case .setupFailed(let detail):
                "เตรียมแปลงวิดีโอไม่สำเร็จ: \(detail)"
            case .writeFailed(let detail):
                "แปลงวิดีโอไม่สำเร็จ: \(detail)"
            }
        }
    }

    /// Re-encodes `input` and returns a new file in `directory`.
    ///
    /// The caller owns the returned file and is expected to delete it once it has been uploaded.
    nonisolated static func transcode(
        _ input: URL,
        to directory: URL = FileManager.default.temporaryDirectory
    ) async throws -> URL {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: input)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let audioTrack = try await firstPlainAudioTrack(in: asset)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let size = outputSize(naturalSize: naturalSize, transform: transform)

        let output = directory.appending(path: "marauders-transcoded-\(UUID().uuidString).mp4")

        do {
            try await encode(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                size: size,
                transform: transform,
                output: output
            )
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        return output
    }

    /// The size the clip is decoded at, in its own unrotated orientation.
    ///
    /// The rotation lives in the track's transform, not in its pixels, so the frame is encoded at
    /// the natural size and the transform is carried onto the output. Scaling the displayed size
    /// instead would squash a rotated clip by its aspect ratio.
    nonisolated static func outputSize(
        naturalSize: CGSize,
        transform: CGAffineTransform,
        maxShortSide: Int = ClipTranscoder.maxShortSide
    ) -> (width: Int, height: Int) {
        let display = naturalSize.applying(transform)
        let shortest = min(abs(display.width), abs(display.height))
        let factor = shortest > Double(maxShortSide) ? Double(maxShortSide) / shortest : 1

        return (even(naturalSize.width * factor), even(naturalSize.height * factor))
    }

    nonisolated static func fourCCString(_ code: FourCharCode) -> String {
        var text = String(bytes: [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ], encoding: .ascii) ?? ""

        // The code is padded with NULs to four bytes, so the padding has to come off before it can
        // be compared against a literal such as "aac".
        while let last = text.last, last.unicodeScalars.first?.value == 0 || last == " " {
            text.removeLast()
        }
        return text
    }

    nonisolated static func isPlainAudio(_ code: FourCharCode) -> Bool {
        plainAudioTypes.contains(fourCCString(code))
    }

    private nonisolated static func even(_ value: Double) -> Int {
        max(2, Int(value.rounded()) & ~1)
    }

    private nonisolated static func firstPlainAudioTrack(in asset: AVAsset) async throws -> AVAssetTrack? {
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let formats = try await track.load(.formatDescriptions)
            if let first = formats.first, isPlainAudio(CMFormatDescriptionGetMediaSubType(first)) {
                return track
            }
        }
        return nil
    }

    private nonisolated static func encode(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        size: (width: Int, height: Int),
        transform: CGAffineTransform,
        output: URL
    ) async throws {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw Failure.setupFailed(error.localizedDescription)
        }
        // Moves the metadata to the front in the same pass, so no second remux is needed.
        writer.shouldOptimizeForNetworkUse = true

        let videoInput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoInput.alwaysCopiesSampleData = false
        reader.add(videoInput)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitrate,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoProfileLevelKey: kVTProfileLevel_H264_High_AutoLevel,
        ]
        let videoOutput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        videoOutput.expectsMediaDataInRealTime = false
        videoOutput.transform = transform
        writer.add(videoOutput)

        var audioInput: AVAssetReaderTrackOutput?
        var audioOutput: AVAssetWriterInput?
        if let audioTrack {
            // The reader can only hand over uncompressed samples, so it is asked for PCM and the
            // writer encodes it back to AAC. Giving the reader the writer's settings would ask for
            // a compressed output it cannot produce.
            let source = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVNumberOfChannelsKey: audioChannels,
                AVSampleRateKey: audioSampleRate,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(source)

            let sink = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: audioChannels,
                AVSampleRateKey: audioSampleRate,
                AVEncoderBitRateKey: audioBitrate,
            ])
            sink.expectsMediaDataInRealTime = false
            writer.add(sink)

            audioInput = source
            audioOutput = sink
        }

        guard reader.startReading() else {
            throw Failure.setupFailed(reader.error?.localizedDescription ?? "อ่านคลิปไม่ได้")
        }
        guard writer.startWriting() else {
            throw Failure.setupFailed(writer.error?.localizedDescription ?? "เริ่มเขียนไฟล์ไม่ได้")
        }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        pump(from: videoInput, to: videoOutput, on: DispatchQueue(label: "marauders.transcode.video"), group: group)
        if let audioInput, let audioOutput {
            pump(from: audioInput, to: audioOutput, on: DispatchQueue(label: "marauders.transcode.audio"), group: group)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) {
                writer.finishWriting { continuation.resume() }
            }
        }

        guard writer.status == .completed else {
            throw Failure.writeFailed(writer.error?.localizedDescription ?? "เขียนไฟล์ไม่สำเร็จ")
        }
    }

    /// Drains one track into another on its own queue.
    ///
    /// `markAsFinished` is called exactly once and the block is not entered again afterwards, so
    /// each `group.enter()` is matched by a single `group.leave()`.
    private nonisolated static func pump(
        from source: AVAssetReaderTrackOutput,
        to sink: AVAssetWriterInput,
        on queue: DispatchQueue,
        group: DispatchGroup
    ) {
        // The media block is `@Sendable`, but the reader and writer are not, and AVFoundation
        // offers no Sendable spelling for them. The block is the only thing that touches these
        // two objects, so handing them over as unchecked sendable is safe here.
        nonisolated(unsafe) let source = source
        nonisolated(unsafe) let sink = sink

        group.enter()
        sink.requestMediaDataWhenReady(on: queue) {
            while sink.isReadyForMoreMediaData {
                guard let sample = source.copyNextSampleBuffer() else {
                    sink.markAsFinished()
                    group.leave()
                    return
                }
                guard sink.append(sample) else {
                    sink.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}
