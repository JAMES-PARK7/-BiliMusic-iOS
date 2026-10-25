import Capacitor
import AVFoundation
import MediaPlayer
import UIKit

@objc(NativePlayerPlugin)
public class NativePlayerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativePlayerPlugin"
    public let jsName = "NativePlayer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setQueue", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "next", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "previous", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getState", returnType: CAPPluginReturnPromise),
    ]
    public override func load() {
        Task { @MainActor [weak self] in
            NativePlayback.shared.notify = { [weak self] state in self?.notifyListeners("playerState", data: state, retainUntilConsumed: true) }
        }
    }
    @objc func setQueue(_ call: CAPPluginCall) {
        let tracks = (call.options["tracks"] as? [[String: Any]] ?? []).compactMap(BiliTrack.init)
        Task { @MainActor in NativePlayback.shared.setQueue(tracks, index: call.getInt("startIndex") ?? 0, position: call.getDouble("position") ?? 0, autoplay: call.getBool("autoplay") ?? false, options: call.options); call.resolve() }
    }
    @objc func play(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.play(); call.resolve() } }
    @objc func pause(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.pause(); call.resolve() } }
    @objc func next(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.next(manual: true); call.resolve() } }
    @objc func previous(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.previous(); call.resolve() } }
    @objc func seek(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.seek(call.getDouble("position") ?? 0); call.resolve() } }
    @objc func configure(_ call: CAPPluginCall) { Task { @MainActor in NativePlayback.shared.configure(call.options); call.resolve() } }
    @objc func getState(_ call: CAPPluginCall) { Task { @MainActor in call.resolve(NativePlayback.shared.state()) } }
}

@MainActor
final class NativePlayback {
    static let shared = NativePlayback()
    var notify: (([String: Any]) -> Void)?
    private let player = AVPlayer()
    private var tracks: [BiliTrack] = []
    private var index = 0
    private var generation = 0
    private var shouldPlay = false
    private var loading = false
    private var repeatMode = "none"
    private var shuffled = false
    private var autoPlay = true
    private var lastError: String?
    private var loader: MediaResourceLoader?
    private var sourceURLs: [URL] = []
    private var sourceIndex = 0
    private var loadedTrackID = ""
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var notifications: [NSObjectProtocol] = []
    private var history: [String] = []
    private var played: Set<String> = []
    private var artwork: UIImage?
    private var artworkID = ""

    private var track: BiliTrack? { tracks.indices.contains(index) ? tracks[index] : nil }
    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.emit() }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.publish() }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in if let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem, self.loadedTrackID == self.track?.id { self.next(manual: false) } }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.emit() } })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor in
                guard let self = self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.player.pause(); self.publish() }
                else if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0 && self.shouldPlay { self.play() }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        })
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in guard let self = self else { return }; if self.shouldPlay { self.pause() } else { self.play() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next(manual: true) }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }

    func configure(_ options: [AnyHashable: Any]) {
        if let mode = options["repeatMode"] as? String, ["none", "one", "all"].contains(mode) { repeatMode = mode }
        if let value = options["shuffled"] as? Bool { if value != shuffled { played = Set(track.map { [$0.id] } ?? []) }; shuffled = value }
        if let value = options["autoPlay"] as? Bool { autoPlay = value }
        if let value = options["volume"] as? NSNumber { player.volume = Float(min(1, max(0, value.doubleValue))) }
        if let value = options["muted"] as? Bool { player.isMuted = value }
    }

    func setQueue(_ nextTracks: [BiliTrack], index desiredIndex: Int, position: Double, autoplay: Bool, options: [AnyHashable: Any]) {
        let previousID = track?.id
        tracks = nextTracks
        index = min(max(0, desiredIndex), max(0, tracks.count - 1))
        configure(options)
        shouldPlay = autoplay
        guard let track = track else {
            generation += 1; loading = false; player.pause(); player.replaceCurrentItem(with: nil); loader?.close(); loader = nil; loadedTrackID = ""; sourceURLs = []
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]); emit(); return
        }
        if previousID == track.id, player.currentItem != nil, loadedTrackID == track.id {
            if autoplay { play() } else { pause() }
            return
        }
        history = history.filter { old in nextTracks.contains { $0.id == old } }
        played = Set([track.id])
        loadCurrent(position: position)
    }

    func play() {
        guard track != nil else { return }
        shouldPlay = true
        guard player.currentItem != nil, loadedTrackID == track?.id else { if !loading { loadCurrent(position: 0) }; return }
        do { try activateSession(); player.play(); publish() }
        catch { fail(error) }
    }
    func pause() { shouldPlay = false; player.pause(); publish() }
    func seek(_ position: Double) {
        let value = max(0, min(position.isFinite ? position : 0, duration() > 0 ? duration() : .greatestFiniteMagnitude))
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in Task { @MainActor in self?.publish() } }
    }
    func next(manual: Bool) {
        guard !tracks.isEmpty else { return }
        if !manual && repeatMode == "one" { seek(0); play(); return }
        if !manual && !autoPlay { pause(); return }
        let oldID = track?.id
        if shuffled && tracks.count > 1 {
            var candidates = tracks.indices.filter { !played.contains(tracks[$0].id) && $0 != index }
            if candidates.isEmpty {
                if !manual && repeatMode == "none" { pause(); return }
                played.removeAll(); candidates = tracks.indices.filter { $0 != index }
            }
            index = candidates.randomElement() ?? index
        } else {
            if index + 1 >= tracks.count && !manual && repeatMode == "none" { pause(); return }
            index = (index + 1) % tracks.count
        }
        if let oldID = oldID { history.append(oldID); if history.count > 100 { history.removeFirst() } }
        if let track = track { played.insert(track.id) }
        shouldPlay = true; loadCurrent(position: 0)
    }
    func previous() {
        guard !tracks.isEmpty else { return }
        if player.currentTime().seconds.isFinite && player.currentTime().seconds > 3 { seek(0); return }
        if shuffled, let oldID = history.popLast(), let oldIndex = tracks.firstIndex(where: { $0.id == oldID }) { index = oldIndex }
        else { index = (index - 1 + tracks.count) % tracks.count }
        shouldPlay = true; loadCurrent(position: 0)
    }

    private func activateSession() throws {
        do { try PlaybackAudioSession.activate() }
        catch { let detail = error as NSError; throw BiliError.message("音频输出启动失败（\(detail.code)）：\(detail.localizedDescription)") }
    }
    private func loadCurrent(position: Double) {
        guard let selected = track else { return }
        generation += 1; let requestGeneration = generation
        loading = true; lastError = nil; sourceURLs = []; player.pause(); publish()
        Task {
            do {
                let urls = try await BiliNetwork.shared.resolveSources(selected)
                guard requestGeneration == generation else { return }
                sourceURLs = urls; sourceIndex = 0
                openSource(position: position, requestGeneration: requestGeneration)
            } catch { if requestGeneration == generation { fail(error) } }
        }
    }
    private func openSource(position: Double, requestGeneration: Int) {
        guard requestGeneration == generation, sourceURLs.indices.contains(sourceIndex), let selected = track else { return }
        statusObservation = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        loader?.close()
        let resourceLoader = MediaResourceLoader(); loader = resourceLoader
        let item = AVPlayerItem(asset: resourceLoader.asset(sourceURLs[sourceIndex]))
        loading = true
        loadedTrackID = selected.id
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor in
                guard let self = self, requestGeneration == self.generation, observed === self.player.currentItem else { return }
                if observed.status == .failed {
                    if self.sourceIndex + 1 < self.sourceURLs.count {
                        let time = self.player.currentTime().seconds
                        self.sourceIndex += 1
                        self.openSource(position: time.isFinite && time > 0 ? time : position, requestGeneration: requestGeneration)
                    } else { self.fail(observed.error ?? BiliError.message("音频加载失败，请重试")) }
                    return
                }
                if observed.status == .readyToPlay {
                    self.loading = false
                    if position > 0 { self.seek(position) }
                    if self.shouldPlay { self.play() } else { self.publish() }
                }
            }
        }
        do { if shouldPlay { try activateSession(); player.play() } }
        catch { fail(error); return }
        updateArtwork(selected)
        publish()
    }
    private func fail(_ error: Error) { loading = false; shouldPlay = false; player.pause(); lastError = error.localizedDescription; publish() }
    private func duration() -> Double {
        let actual = loadedTrackID == track?.id ? (player.currentItem?.duration.seconds ?? 0) : 0
        return actual.isFinite && actual > 0 ? actual : (track?.duration ?? 0)
    }
    func state() -> [String: Any] {
        let time = loadedTrackID == track?.id ? player.currentTime().seconds : 0
        var result: [String: Any] = ["trackId": track?.id ?? "", "isPlaying": shouldPlay && player.timeControlStatus == .playing, "position": time.isFinite ? time : 0, "duration": duration(), "isLoading": loading || (shouldPlay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate)]
        if let message = lastError { result["error"] = message }
        return result
    }
    private func emit() {
        guard UIApplication.shared.applicationState != .background else { return }
        notify?(state()); lastError = nil
    }
    private func publish() {
        guard let track = track else { emit(); return }
        let time = loadedTrackID == track.id ? player.currentTime().seconds : 0
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: "BiliMusic", MPMediaItemPropertyPlaybackDuration: duration(), MPNowPlayingInfoPropertyElapsedPlaybackTime: time.isFinite ? time : 0, MPNowPlayingInfoPropertyPlaybackRate: shouldPlay && player.timeControlStatus == .playing ? 1.0 : 0.0]
        if let image = artwork, artworkID == track.id { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        emit()
    }
    private func updateArtwork(_ track: BiliTrack) {
        artwork = nil; artworkID = track.id
        guard let url = URL(string: track.coverURL), url.scheme == "https", let host = url.host, BiliPolicy.matches(host, "hdslb.com") else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(for: BiliPolicy.request(url)), let image = UIImage(data: data), self.track?.id == track.id { artwork = image; artworkID = track.id; publish() }
        }
    }
}
