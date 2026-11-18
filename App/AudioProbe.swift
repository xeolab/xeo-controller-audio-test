import AVFoundation
import Foundation

struct AudioSample: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL?
    var speakers: [String] = []
    var isAppleAtmos = false
    var isImported = false

    static let speakers51 = ["左前", "右前", "中置", "低频", "左侧", "右侧"]
    static let samples = [
        AudioSample(id: "stereo", title: "立体声", subtitle: "离线 · 左右定位",
                    url: Bundle.main.url(forResource: "stereo", withExtension: "flac"), speakers: ["左", "右"]),
        AudioSample(id: "surround51", title: "5.1 环绕", subtitle: "离线 · 6 路顺序定位",
                    url: Bundle.main.url(forResource: "surround51", withExtension: "flac"), speakers: speakers51),
        AudioSample(id: "surround71", title: "7.1 环绕", subtitle: "离线 · 8 路顺序定位",
                    url: Bundle.main.url(forResource: "surround71", withExtension: "flac"),
                    speakers: speakers51 + ["左后", "右后"]),
        AudioSample(id: "atmos", title: "Dolby Atmos", subtitle: "联网 · Apple 官方 HLS 音轨",
                    url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/Job932393e2-1e4f-4fdb-ab59-0d201f752656-107660254-Transcode_audio_full_en_atmos_0_1-en_audio/prog_index.m3u8"),
                    isAppleAtmos: true)
    ]
}

private func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
    guard bytes.allSatisfy({ (32...126).contains($0) }) else { return String(format: "0x%08X", value) }
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
}

private func audioFormatName(_ stream: AudioStreamBasicDescription) -> String {
    switch stream.mFormatID {
    case kAudioFormatLinearPCM:
        let bits = stream.mBitsPerChannel
        guard bits > 0 else { return "线性 PCM" }
        let type = stream.mFormatFlags & kAudioFormatFlagIsFloat == 0 ? "整数" : "浮点"
        return "线性 PCM · \(bits) bit \(type)"
    case kAudioFormatFLAC: return "FLAC"
    case kAudioFormatAppleLossless: return "Apple Lossless (ALAC)"
    case kAudioFormatMPEG4AAC: return "AAC"
    case kAudioFormatAC3: return "Dolby Digital (AC-3)"
    case kAudioFormatEnhancedAC3: return "Dolby Digital Plus (EC-3)"
    default: return fourCC(stream.mFormatID)
    }
}

private func streamSummary(_ stream: AudioStreamBasicDescription) -> String {
    let channels = stream.mChannelsPerFrame > 0 ? "\(stream.mChannelsPerFrame) 声道" : "声道数未知"
    let rate = stream.mSampleRate > 0 ? "\(Int(stream.mSampleRate.rounded())) Hz" : "采样率未知"
    return "\(audioFormatName(stream)) · \(channels) · \(rate)"
}

struct AudioRouteSnapshot: Equatable {
    struct Port: Equatable {
        let name: String
        let type: String
        let channels: Int?
        let spatialEnabled: Bool
    }

    let ports: [Port]
    let currentChannels: Int
    let maximumChannels: Int
    let sampleRate: Int
    let outputFormat: String?

    var assessment: String {
        if currentChannels > 2 {
            return "iOS 正报告 \(currentChannels) 路输出，可用定位样本核对各路。"
        }
        if ports.contains(where: \.spatialEnabled) {
            return "系统允许空间音频，可用多声道片源试听当前设备的空间化效果。"
        }
        if maximumChannels > 2 {
            return "当前路由申报最多 \(maximumChannels) 路，此时使用 \(currentChannels) 路。"
        }
        return "此时系统未报告多声道输出或可用的空间音频。"
    }
}

@MainActor
final class AudioProbe: ObservableObject {
    enum PlaybackState: Equatable {
        case idle, loading, playing, paused, finished, failed

        var title: String {
            switch self {
            case .idle: return "待播放"
            case .loading: return "正在加载或缓冲"
            case .playing: return "正在播放"
            case .paused: return "已暂停"
            case .finished: return "播放结束"
            case .failed: return "播放失败"
            }
        }
    }

    let player = AVPlayer()
    @Published private(set) var selected = AudioSample.samples[0]
    @Published private(set) var imported: AudioSample?
    @Published private(set) var state = PlaybackState.idle
    @Published private(set) var route: AudioRouteSnapshot?
    @Published private(set) var sourceFormats: [String] = []
    @Published private(set) var formatsAreActiveTracks = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var failure: String?
    @Published var spatialization = true {
        didSet { configureSpatialization(for: player.currentItem) }
    }

    private let session = AVAudioSession.sharedInstance()
    private var active = false
    private var securityScopedURL: URL?
    private var itemStatus: NSKeyValueObservation?
    private var playerStatus: NSKeyValueObservation?
    private var trackObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var inspection: Task<Void, Never>?

    init() {
        playerStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updatePlaybackState() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.12, preferredTimescale: 600),
                                                       queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem != nil, self.state == .playing, time.seconds.isFinite else { return }
                self.elapsed = time.seconds
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var speakerIndex: Int? {
        guard state == .playing || state == .paused else { return nil }
        let index = Int(elapsed / 0.95)
        return selected.speakers.indices.contains(index) ? index : nil
    }

    func select(_ sample: AudioSample) {
        guard selected != sample else { return }
        stop()
        selected = sample
        sourceFormats = []
        formatsAreActiveTracks = false
    }

    func acceptImport(_ url: URL) {
        let sample = AudioSample(id: "import", title: url.lastPathComponent, subtitle: "从文件导入",
                                 url: url, isImported: true)
        imported = sample
        select(sample)
    }

    func reportImportError(_ error: Error) {
        failure = "导入失败 · \(error.localizedDescription)"
    }

    func play() {
        if state == .paused, player.currentItem != nil {
            player.play()
            return
        }
        stop()
        sourceFormats = []
        formatsAreActiveTracks = false
        guard let url = selected.url else {
            fail("找不到样本文件")
            return
        }
        if selected.isImported && url.startAccessingSecurityScopedResource() { securityScopedURL = url }
        do {
            try activateSession()
        } catch {
            fail(error.localizedDescription)
            return
        }
        let item = AVPlayerItem(url: url)
        configureSpatialization(for: item)
        state = .loading
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        refreshRoute()
    }

    func pause() {
        player.pause()
        if state == .playing || state == .loading { state = .paused }
    }

    func stop() {
        releaseItem()
        elapsed = 0
        failure = nil
        state = .idle
    }

    func stopAndDeactivate() {
        stop()
        if active { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        active = false
        route = nil
    }

    func inspectRoute() {
        do {
            try activateSession()
            failure = nil
            refreshRoute()
        } catch {
            failure = "无法激活音频会话 · \(error.localizedDescription)"
        }
    }

    func refreshRoute() {
        guard active else { return }
        let ports = session.currentRoute.outputs.map {
            AudioRouteSnapshot.Port(name: $0.portName, type: $0.portType.rawValue,
                                    channels: $0.channels?.count, spatialEnabled: $0.isSpatialAudioEnabled)
        }
        let probe = AVAudioEngine()
        let stream = probe.outputNode.outputFormat(forBus: 0).streamDescription.pointee
        let output = stream.mSampleRate > 0 && stream.mChannelsPerFrame > 0 ? streamSummary(stream) : nil
        route = AudioRouteSnapshot(ports: ports, currentChannels: session.outputNumberOfChannels,
                                   maximumChannels: session.maximumOutputNumberOfChannels,
                                   sampleRate: Int(session.sampleRate.rounded()), outputFormat: output)
    }

    func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        stopAndDeactivate()
        failure = "系统已中断音频会话，可重新播放。"
    }

    private func activateSession() throws {
        guard !active else { return }
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        active = true
    }

    private func configureSpatialization(for item: AVPlayerItem?) {
        item?.allowedAudioSpatializationFormats = spatialization ? .multichannel : []
    }

    private func observe(_ item: AVPlayerItem) {
        itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.inspectTracks(item)
                    self.refreshRoute()
                case .failed:
                    self.fail(item.error?.localizedDescription ?? "AVPlayer 无法打开该片段")
                default: break
                }
            }
        }
        trackObservation = item.observe(\.tracks, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item, item.status == .readyToPlay else { return }
                self.inspectTracks(item)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.state = .finished
                self.refreshRoute()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                                 object: item, queue: .main) { [weak self, weak item] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.fail(error?.localizedDescription ?? "回放中断")
            }
        }
    }

    private func inspectTracks(_ item: AVPlayerItem) {
        inspection?.cancel()
        let tracks = item.tracks.filter(\.isEnabled).compactMap(\.assetTrack).filter { $0.mediaType == .audio }
        inspection = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let activeFormats = await Self.readFormats(from: tracks)
            var formats = activeFormats
            if formats.isEmpty, let assetTracks = try? await item.asset.loadTracks(withMediaType: .audio) {
                formats = await Self.readFormats(from: assetTracks)
            }
            guard !Task.isCancelled, self.player.currentItem === item else { return }
            self.sourceFormats = formats
            self.formatsAreActiveTracks = !activeFormats.isEmpty
        }
    }

    private static func readFormats(from tracks: [AVAssetTrack]) async -> [String] {
        var summaries: [String] = []
        for track in tracks {
            guard let formats = try? await track.load(.formatDescriptions) else { continue }
            for format in formats {
                guard let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { continue }
                let summary = streamSummary(stream)
                if !summaries.contains(summary) { summaries.append(summary) }
            }
        }
        return summaries
    }

    private func updatePlaybackState() {
        guard player.currentItem != nil, state != .finished, state != .failed else { return }
        switch player.timeControlStatus {
        case .playing:
            if state != .playing { refreshRoute() }
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            if state != .paused { state = .loading }
        case .paused:
            if state == .playing { state = .paused }
        @unknown default: break
        }
    }

    private func fail(_ description: String) {
        releaseItem()
        failure = description
        state = .failed
    }

    private func releaseItem() {
        inspection?.cancel()
        inspection = nil
        itemStatus = nil
        trackObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
