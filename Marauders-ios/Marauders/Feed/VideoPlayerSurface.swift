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
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.setPlayer(player, gravity: gravity)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.setPlayer(player, gravity: gravity)
    }
}

/// Fills the whole screen with the same clip and blurs it, so a landscape video on a
/// portrait phone shows the entire frame without leaving large dead bars. Portrait clips
/// cover the whole screen on their own, in which case the backdrop simply matches.
struct AmbientVideoBackdrop: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AmbientBackdropView {
        let view = AmbientBackdropView()
        view.setPlayer(player)
        return view
    }

    func updateUIView(_ uiView: AmbientBackdropView, context: Context) {
        uiView.setPlayer(player)
    }
}

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    func setPlayer(_ player: AVPlayer?, gravity: AVLayerVideoGravity) {
        guard let playerLayer = layer as? AVPlayerLayer else { return }
        if playerLayer.player !== player {
            playerLayer.player = player
        }
        if playerLayer.videoGravity != gravity {
            playerLayer.videoGravity = gravity
        }
    }
}

final class AmbientBackdropView: UIView {
    private let surface = PlayerSurfaceView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let dimView = UIView()

    init() {
        super.init(frame: .zero)
        clipsToBounds = true

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        for subview in [surface, blurView, dimView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: trailingAnchor),
                subview.topAnchor.constraint(equalTo: topAnchor),
                subview.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        surface.setPlayer(nil, gravity: .resizeAspectFill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setPlayer(_ player: AVPlayer?) {
        surface.setPlayer(player, gravity: .resizeAspectFill)
    }
}
