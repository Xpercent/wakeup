import AVFoundation
import Combine

final class AlarmAudioPlayer: ObservableObject {
    private var player: AVAudioPlayer?

    func start(soundURL: URL?) {
        guard player?.isPlaying != true, let soundURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = -1
            player.volume = 1
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit { stop() }
}
