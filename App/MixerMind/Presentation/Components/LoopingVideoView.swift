import SwiftUI
import AVFoundation

struct LoopingVideoView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player, gravity: gravity)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.updatePlayer(player, gravity: gravity)
    }

    class PlayerUIView: UIView {
        private let playerLayer = AVPlayerLayer()

        init(player: AVPlayer, gravity: AVLayerVideoGravity) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = gravity
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        func updatePlayer(_ player: AVPlayer, gravity: AVLayerVideoGravity) {
            if playerLayer.player !== player {
                playerLayer.player = player
            }
            if playerLayer.videoGravity != gravity {
                playerLayer.videoGravity = gravity
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
