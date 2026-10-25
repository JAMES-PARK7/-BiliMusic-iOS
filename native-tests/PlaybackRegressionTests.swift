import AVFoundation
import XCTest
@testable import BiliMusicPlaybackCore

final class SourceSelectionTests: XCTestCase {
    func testUsesAACBackupWhenPrimaryMCDNHasAnUnsupportedPort() throws {
        let primary = "https://xy123x123x123x123xy.mcdn.bilivideo.cn:8082/audio.m4s?sig=a%2Fb%2Bc"
        let best = "https://upos-sz-estgoss.bilivideo.com/audio.m4s?sig=a%2Fb%2Bc&deadline=1"
        let lower = "https://upos-sz-mirrorhw.bilivideo.com/lower.m4s"
        let play: [String: Any] = ["dash": ["audio": [
            ["bandwidth": 64000, "mimeType": "audio/mp4", "codecs": "mp4a.40.2", "base_url": lower],
            ["bandwidth": 192000, "mimeType": "audio/mp4", "codecs": "mp4a.40.2", "baseUrl": primary, "backupUrl": [best, best]],
            ["bandwidth": 300000, "mimeType": "audio/webm", "codecs": "opus", "baseUrl": "https://upos-sz-mirrorhw.bilivideo.com/opus.webm"]
        ]]]
        XCTAssertEqual(try BiliPolicy.audioSources(play).map(\.absoluteString), [best, lower])
    }

    func testUpgradesOfficialHTTPURLsWithoutChangingTheSignature() throws {
        let query = "?deadline=1&sig=A%2FB%2BC%3D&order=2+3"
        XCTAssertEqual(try BiliPolicy.mediaURL("http://upos-sz-estgoss.bilivideo.com:80/audio.m4s" + query).absoluteString, "https://upos-sz-estgoss.bilivideo.com/audio.m4s" + query)
        XCTAssertEqual(try BiliPolicy.mediaURL("//upos-sz-estgoss.bilivideo.com/audio.m4s" + query).absoluteString, "https://upos-sz-estgoss.bilivideo.com/audio.m4s" + query)
    }

    func testRejectsUntrustedOriginsAndNonstandardPorts() {
        for address in ["https://bilivideo.com.example.org/audio", "https://attacker.example/audio", "https://user:password@upos-sz-estgoss.bilivideo.com/audio", "https://upos-sz-estgoss.bilivideo.com:8082/audio", "file:///private/audio.m4a"] {
            XCTAssertThrowsError(try BiliPolicy.mediaURL(address), address)
        }
    }

    func testMissingAudioAndUnusableEndpointsProduceAnError() {
        XCTAssertThrowsError(try BiliPolicy.audioSources([:]))
        XCTAssertThrowsError(try BiliPolicy.audioSources(["dash": ["audio": [["baseUrl": "https://attacker.example/audio"]]]]))
    }
}

@MainActor
final class NativePlaybackTests: XCTestCase {
    func testActivatesPlaybackAudioSessionWithoutInvalidCategoryOptions() throws {
        XCTAssertNoThrow(try PlaybackAudioSession.activate())
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func testResourceLoaderCanDecodePlayAndSeekRangedAACAudio() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let loader = MediaResourceLoader(configuration: configuration)
        let asset = loader.asset(try BiliPolicy.mediaURL("https://upos-sz-estgoss.bilivideo.com/fixture.m4s?signature=fixture"))
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        defer {
            player.pause(); player.replaceCurrentItem(with: nil); loader.close()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        try PlaybackAudioSession.activate()
        for _ in 0..<150 {
            if item.status != .unknown { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(item.status, .readyToPlay, item.error?.localizedDescription ?? "Audio item never became ready")
        guard item.status == .readyToPlay else { return }
        XCTAssertGreaterThan(item.duration.seconds, 3)
        player.play()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertGreaterThan(player.currentTime().seconds, 0.1, "The native playback clock must advance")
        player.pause()
        let seeked = await player.seek(to: CMTime(seconds: 2, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(seeked)
        XCTAssertEqual(player.currentTime().seconds, 2, accuracy: 0.1)
    }
}

private final class FixtureProtocol: URLProtocol {
    private static let audio: Data = {
        let url = Bundle.module.url(forResource: "tone", withExtension: "m4a", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "upos-sz-estgoss.bilivideo.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let audio = Self.audio
        let range = request.value(forHTTPHeaderField: "Range")?.replacingOccurrences(of: "bytes=", with: "").split(separator: "-", omittingEmptySubsequences: false)
        let start = min(audio.count - 1, max(0, range?.first.flatMap { Int($0) } ?? 0))
        let end = min(audio.count - 1, range?.last.flatMap { Int($0) } ?? audio.count - 1)
        let data = audio.subdata(in: start..<max(start, end + 1))
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/octet-stream", "Content-Length": String(data.count), "Content-Range": "bytes \(start)-\(end)/\(audio.count)", "Accept-Ranges": "bytes"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
