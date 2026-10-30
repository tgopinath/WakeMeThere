import AVFoundation
import AudioToolbox

/// Plays a looping alarm tone (ignores the silent switch) plus repeating vibration.
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    private var vibrationTimer: Timer?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        if player == nil {
            player = try? AVAudioPlayer(data: AlarmTone.wav(repeats: 1))
            player?.numberOfLoops = -1
        }
        player?.volume = 1
        player?.play()

        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationTimer?.invalidate()
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Synthesises the alarm tone so the app ships without audio assets.
enum AlarmTone {
    static let notificationSoundName = "arrival.wav"

    /// Writes a ~25s version into Library/Sounds so notifications can use it as a custom sound.
    static func installNotificationSound() {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = library.appendingPathComponent("Sounds", isDirectory: true)
        let url = dir.appendingPathComponent(notificationSoundName)
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? wav(repeats: 20).write(to: url)
    }

    /// One pattern is a double "bee-boop" chirp followed by a short rest (~1.2s).
    static func wav(repeats: Int) -> Data {
        let sampleRate = 44_100.0
        var samples: [Int16] = []

        func tone(_ frequency: Double, _ seconds: Double) {
            let count = Int(sampleRate * seconds)
            let fade = 300.0
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = min(1, Double(i) / fade, Double(count - i) / fade)
                // Fundamental plus a soft overtone so it cuts through road/train noise.
                let wave = 0.75 * sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)
                samples.append(Int16(wave * envelope * 0.85 * Double(Int16.max)))
            }
        }
        func rest(_ seconds: Double) {
            samples += Array(repeating: 0, count: Int(sampleRate * seconds))
        }

        for _ in 0..<max(1, repeats) {
            tone(988, 0.13); rest(0.05); tone(1319, 0.13); rest(0.09)
            tone(988, 0.13); rest(0.05); tone(1319, 0.13); rest(0.5)
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                       // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2) // sample rate, byte rate
        append(UInt16(2)); append(UInt16(16))                      // block align, bits/sample
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.forEach { append($0) }
        return data
    }
}
