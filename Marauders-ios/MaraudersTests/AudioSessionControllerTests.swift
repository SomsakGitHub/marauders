//
//  AudioSessionControllerTests.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 30/9/2569 BE.
//

import AVFoundation
import Testing
@testable import Marauders

@Suite("AudioSessionController")
struct AudioSessionControllerTests {
    @Test("activation configures a category and mode that AVAudioSession accepts")
    func activationIsValid() throws {
        let controller = AudioSessionController.shared
        defer { controller.deactivate() }

        // An illegal pairing, such as .ambient with .moviePlayback, throws OSStatus -50 here
        // rather than only failing on a device.
        try #expect(throws: Never.self) {
            try controller.configure()
        }

        let session = AVAudioSession.sharedInstance()
        #expect(session.category == .ambient)
        #expect(session.mode == .default)
        #expect(session.categoryOptions.contains(.mixWithOthers))
    }

    @Test("deactivation releases the session without throwing")
    func deactivationIsValid() {
        let controller = AudioSessionController.shared
        controller.activate()
        controller.deactivate()
        controller.deactivate()
    }
}
