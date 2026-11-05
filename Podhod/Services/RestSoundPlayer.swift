import AVFoundation
import Combine

@MainActor
final class RestSoundPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing: RestSignalSound?
    @Published private(set) var message: String?
    private var player: AVAudioPlayer?

    static func resourceURL(_ file: String) -> URL? {
        Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: (file as NSString).pathExtension)
    }
    static func isValidResource(_ file: String) -> Bool {
        guard let url = resourceURL(file), let audio = try? AVAudioFile(forReading: url), audio.processingFormat.sampleRate > 0 else { return false }
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        return duration > 0 && duration < 30
    }
    func toggle(_ sound: RestSignalSound) {
        if playing == sound { stop(); return }
        stop()
        guard let file = sound.fileName, Self.isValidResource(file), let url = Self.resourceURL(file) else {
            message = sound == .system ? "Системный звук доступен только в настоящем сигнале. Используй «Проверить сигнал» на предыдущем экране." : "Не удалось открыть звуковой файл."
            return
        }
        do {
            // User-initiated preview only. It is stopped on leaving the screen or backgrounding.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self; audio.prepareToPlay()
            guard audio.play() else { throw CocoaError(.fileReadUnknown) }
            player = audio; playing = sound; message = nil
        } catch { message = "Не удалось прослушать звук. Попробуй другой сигнал."; stop() }
    }
    func stop() {
        player?.stop(); player = nil; playing = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.stop()
        }
    }
}
