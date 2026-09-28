//
//  VideoPlayerSurface.swift
//  Marauders
//
//  Created by tiscomacnb2486 on 29/9/2569 BE.
//

import AVFoundation
import SwiftUI

struct VideoPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.setPlayer(player)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.setPlayer(player)
    }
}

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    func setPlayer(_ player: AVPlayer?) {
        guard let playerLayer = layer as? AVPlayerLayer else { return }
        if playerLayer.player !== player {
            playerLayer.player = player
        }
        playerLayer.videoGravity = .resizeAspectFill
    }
}
