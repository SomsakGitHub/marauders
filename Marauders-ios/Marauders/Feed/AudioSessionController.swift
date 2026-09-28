//
//  AudioSessionController.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import Foundation

final class AudioSessionController {
    static let shared = AudioSessionController()

    private let session = AVAudioSession.sharedInstance()

    private init() {}

    func activate() {
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            assertionFailure("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            assertionFailure("Audio session deactivation failed: \(error.localizedDescription)")
        }
    }
}
