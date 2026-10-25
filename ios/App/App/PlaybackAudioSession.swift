import AVFAudio

enum PlaybackAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback already supports AirPlay. Explicit .allowAirPlay is only
        // valid for playAndRecord and causes a parameter error with playback.
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
}
