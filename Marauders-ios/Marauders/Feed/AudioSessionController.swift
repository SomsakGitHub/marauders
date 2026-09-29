//
//  AudioSessionController.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import Foundation
import os

final class AudioSessionController {
    static let shared = AudioSessionController()

    private let session = AVAudioSession.sharedInstance()
    private let log = Logger(subsystem: "com.somsak.Marauders", category: "AudioSession")

    private init() {}

    /// There is no in-app mute control, so the session has to stay out of the way:
    /// `.ambient` keeps the hardware silent switch working and `.mixWithOthers` means a clip
    /// never stops whatever the user was already listening to.
    ///
    /// The mode is `.default` on purpose: `.moviePlayback` is only legal with the `.playback`
    /// category and pairing it with `.ambient` fails with `OSStatus -50`.
    func configure() throws {
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    func activate() {
        do {
            try configure()
        } catch {
            // Audio is not worth losing the feed over: a session we cannot claim just means the
            // clips stay silent, and the OS will hand it back once the conflict clears.
            log.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log.error("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
