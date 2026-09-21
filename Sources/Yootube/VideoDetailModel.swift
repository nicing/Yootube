@preconcurrency import AVFoundation
import AppKit
import AVKit
import Foundation
import WebKit

enum PlayerDisplayCycleAction: Equatable {
    case enterTheater
    case enterPlayerFullScreen
    case exitPlayerFullScreenAndTheater

    static func resolve(theaterMode: Bool, playerFullScreen: Bool) -> Self {
        if playerFullScreen { return .exitPlayerFullScreenAndTheater }
        return theaterMode ? .enterPlayerFullScreen : .enterTheater
    }
}

@MainActor
final class VideoDetailModel: NSObject, ObservableObject {
    let route: VideoRoute
    @Published private(set) var metadata: VideoMetadata?
    @Published private(set) var error: String?
    @Published private(set) var playerError: String?
    @Published private(set) var playerLoading = true
    @Published private(set) var playerTheaterMode = false
    @Published private(set) var playerFullScreen = false
    @Published private(set) var playerAspectRatio = 16.0 / 9.0
    @Published private(set) var comments: [VideoComment] = []
    @Published private(set) var commentsLoaded = false
    @Published private(set) var commentsLoading = false
    @Published private(set) var commentsError: String?
    @Published private(set) var continuation: String?
    @Published private(set) var cacheError: String?
    @Published private(set) var isPlayingFromCache = false
    @Published var autoplayEnabled: Bool {
        didSet { defaults.set(autoplayEnabled, forKey: Self.autoplayDefaultsKey) }
    }
    let pictureInPictureLayer = AVPlayerLayer()
    private var metadataTask: Task<Void, Never>?
    private var commentsTask: Task<Void, Never>?
    private var pictureInPictureTask: Task<Void, Never>?
    private var pictureInPictureSession: NativePictureInPictureSession?
    private weak var playerHostView: PlayerHostView?
    private let history: WatchHistory
    fileprivate let videoCache: VideoCacheStore
    private let navigate: (URL) -> Void
    private let defaults: UserDefaults
    private var active = true
    private var played = false
    private var recorded = false
    private var autoplayHandled = false

    private static let autoplayDefaultsKey = "videoAutoplayEnabled"

    lazy var player: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.userContentController.add(DetailPlaybackObserver(owner: self), name: "detailPlayback")
        config.userContentController.addUserScript(WKUserScript(source: PlayerSkin.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        return view
    }()

    init(route: VideoRoute, history: WatchHistory,
         videoCache: VideoCacheStore = .shared,
         defaults: UserDefaults = .standard,
         navigate: @escaping (URL) -> Void) {
        self.route = route
        self.history = history
        self.videoCache = videoCache
        self.defaults = defaults
        autoplayEnabled = defaults.object(forKey: Self.autoplayDefaultsKey) as? Bool ?? true
        self.navigate = navigate
        super.init()
        pictureInPictureLayer.videoGravity = .resizeAspect
        metadata = videoCache.entry(for: route.id)?.basicMetadata
        reloadPlayer()
        reload()
    }

    func reload() {
        guard active else { return }
        metadataTask?.cancel()
        error = nil
        metadataTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await VideoRequestRetry.run(maxAttempts: 12, delay: .seconds(1)) {
                    try await VideoAPI.fetch(
                        VideoMetadata.self,
                        path: "api/v1/videos/\(self.route.id)",
                        query: [URLQueryItem(name: "local", value: "true")]
                    )
                }
                try Task.checkCancellation()
                guard active else { return }
                guard value.videoId == route.id else { throw VideoAPI.APIError.unavailable }
                metadata = value
                recordPlaybackIfReady()
            } catch {
                if !Task.isCancelled, active {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func reloadPlayer(forceNetwork: Bool = false) {
        guard active else { return }
        playerError = nil
        playerLoading = true
        playerAspectRatio = 16.0 / 9.0
        if !forceNetwork,
           let page = videoCache.playerPageURL(for: route.id, startValue: route.startTimeValue),
           let readAccess = videoCache.readAccessURL(for: route.id) {
            isPlayingFromCache = true
            player.loadFileURL(page, allowingReadAccessTo: readAccess)
            return
        }
        isPlayingFromCache = false
        player.load(URLRequest(url: route.embedURL))
    }

    func retryPlayback() {
        reloadPlayer()
        if metadata == nil { reload() }
    }

    func togglePlayback() {
        guard active else { return }
        player.evaluateJavaScript("window.yootubeTogglePlayback?.()", completionHandler: nil)
    }

    func toggleTheaterMode() {
        guard active else { return }
        player.evaluateJavaScript("window.yootubeToggleTheaterMode?.()", completionHandler: nil)
    }

    func cycleDisplayMode() {
        guard active else { return }
        let action = PlayerDisplayCycleAction.resolve(
            theaterMode: playerTheaterMode,
            playerFullScreen: playerFullScreen || player.isInFullScreenMode
        )
        switch action {
        case .enterTheater:
            playerTheaterMode = true
            player.evaluateJavaScript("window.yootubeSetTheaterMode?.(true)", completionHandler: nil)
        case .enterPlayerFullScreen:
            guard let screen = player.window?.screen ?? NSScreen.main else { return }
            playerHostView = player.superview as? PlayerHostView
            let presentation = NSApplication.PresentationOptions.autoHideDock.union(.autoHideMenuBar)
            let options: [NSView.FullScreenModeOptionKey: Any] = [
                .fullScreenModeApplicationPresentationOptions: NSNumber(value: presentation.rawValue)
            ]
            if player.enterFullScreenMode(screen, withOptions: options) {
                playerFullScreen = true
                player.evaluateJavaScript("window.yootubeSetPlayerFullScreen?.(true)", completionHandler: nil)
            }
        case .exitPlayerFullScreenAndTheater:
            exitPlayerFullScreen()
            exitTheaterMode()
        }
    }

    func exitPlayerFullScreen() {
        guard active else { return }
        if player.isInFullScreenMode { player.exitFullScreenMode(options: nil) }
        playerFullScreen = false
        player.evaluateJavaScript("window.yootubeSetPlayerFullScreen?.(false)", completionHandler: nil)
        playerHostView?.restoreWebViewLayoutAfterFullScreen()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            self.playerHostView?.restoreWebViewLayoutAfterFullScreen()
        }
    }

    func exitTheaterMode() {
        guard active, playerTheaterMode else { return }
        playerTheaterMode = false
        player.evaluateJavaScript("window.yootubeSetTheaterMode?.(false)", completionHandler: nil)
    }

    func toggleMute() {
        guard active else { return }
        player.evaluateJavaScript("window.yootubeToggleMute?.()", completionHandler: nil)
    }

    func toggleCaptions() {
        guard active else { return }
        player.evaluateJavaScript("window.yootubeToggleCaptions?.()", completionHandler: nil)
    }

    func updateLanguage() {
        guard active else { return }
        let language = AppLanguage.current.playerLanguageCode
        player.evaluateJavaScript("window.yootubeSetLanguage?.('\(language)')", completionHandler: nil)
    }

    func loadComments() {
        guard active, !commentsLoading else { return }
        commentsLoading = true
        commentsError = nil
        commentsTask = Task { [weak self] in
            guard let self else { return }
            defer { commentsLoading = false }
            do {
                let query = continuation.map { [URLQueryItem(name: "continuation", value: $0)] } ?? []
                let page = try await VideoAPI.fetch(VideoComments.self, path: "api/v1/comments/\(route.id)", query: query)
                try Task.checkCancellation()
                guard active else { return }
                var ids = Set(comments.map(\.id))
                comments.append(contentsOf: page.comments.filter { ids.insert($0.id).inserted })
                continuation = page.continuation
                commentsLoaded = true
            } catch {
                if !Task.isCancelled, active { commentsError = L10n.t("评论暂时无法加载，请重试。") }
            }
        }
    }

    func cache(option: VideoCacheOption) {
        guard let metadata else { return }
        cacheError = nil
        videoCache.cache(metadata, option: option)
    }

    func removeCache() {
        guard videoCache.entry(for: route.id) != nil else { return }
        if isPlayingFromCache { reloadPlayer(forceNetwork: true) }
        do {
            try videoCache.remove(videoID: route.id)
        } catch {
            cacheError = L10n.t("无法删除这个视频的本地缓存。")
        }
    }

    func dismissCacheError() {
        cacheError = nil
        videoCache.dismissError(for: route.id)
    }

    func stop() {
        if playerFullScreen || player.isInFullScreenMode { exitPlayerFullScreen() }
        active = false
        metadataTask?.cancel()
        commentsTask?.cancel()
        pictureInPictureTask?.cancel()
        pictureInPictureSession?.cancel()
        pictureInPictureSession = nil
        player.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => v.pause())", completionHandler: nil)
        player.stopLoading()
        player.loadHTMLString("", baseURL: nil)
    }

    fileprivate func didPlay() {
        guard active else { return }
        played = true
        autoplayHandled = false
        recordPlaybackIfReady()
    }

    fileprivate func didEndPlayback() {
        guard active, !autoplayHandled else { return }
        autoplayHandled = true
        guard autoplayEnabled,
              let url = nextAutoplayURL(currentVideoID: route.id,
                                         recommendedVideos: metadata?.recommendedVideos) else { return }
        navigate(url)
    }

    func setPlayerTheaterMode(_ enabled: Bool) {
        guard active else { return }
        playerTheaterMode = enabled
    }

    func setPlayerAspectRatio(_ value: Double) {
        guard active, value.isFinite, (0.4...4).contains(value) else { return }
        playerAspectRatio = value
    }

    fileprivate func requestPictureInPicture(_ playback: WebPlaybackState) {
        guard active, pictureInPictureSession == nil, pictureInPictureTask == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            finishWebPictureInPicture(playback, message: L10n.t("当前 Mac 不支持画中画。"))
            return
        }

        if let cachedURL = videoCache.videoFileURL(for: route.id) {
            startPictureInPicture(sourceURL: cachedURL, playback: playback)
            return
        }

        pictureInPictureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value: VideoMetadata
                if let metadata {
                    value = metadata
                } else {
                    value = try await VideoAPI.fetch(
                        VideoMetadata.self,
                        path: "api/v1/videos/\(route.id)",
                        query: [URLQueryItem(name: "local", value: "true")]
                    )
                    guard value.videoId == route.id else { throw VideoAPI.APIError.unavailable }
                    metadata = value
                }
                try Task.checkCancellation()
                guard active else { return }
                pictureInPictureTask = nil
                guard let sourceURL = value.pictureInPictureURL else {
                    finishWebPictureInPicture(playback, message: L10n.t("当前视频没有可用于画中画的兼容播放源。"))
                    return
                }
                startPictureInPicture(sourceURL: sourceURL, playback: playback)
            } catch is CancellationError {
                pictureInPictureTask = nil
            } catch {
                pictureInPictureTask = nil
                if active {
                    finishWebPictureInPicture(playback, message: L10n.t("暂时无法准备画中画，请稍后重试。"))
                }
            }
        }
    }

    fileprivate func stopPictureInPicture() {
        guard active else { return }
        pictureInPictureTask?.cancel()
        pictureInPictureTask = nil
        if let pictureInPictureSession {
            pictureInPictureSession.stop()
        } else {
            setWebPictureInPictureState("inactive")
        }
    }

    private func startPictureInPicture(sourceURL: URL, playback: WebPlaybackState) {
        guard active, pictureInPictureSession == nil else { return }
        let session = NativePictureInPictureSession(
            sourceURL: sourceURL,
            playerLayer: pictureInPictureLayer,
            playback: playback,
            onStarted: { [weak self] in
                self?.setWebPictureInPictureState("active")
            },
            onStopped: { [weak self] state in
                guard let self else { return }
                pictureInPictureSession = nil
                guard active else { return }
                finishWebPictureInPicture(state)
            },
            onFailed: { [weak self] message in
                guard let self else { return }
                pictureInPictureSession = nil
                guard active else { return }
                finishWebPictureInPicture(playback, message: message)
            }
        )
        pictureInPictureSession = session
        session.start()
    }

    private func setWebPictureInPictureState(_ state: String) {
        guard active else { return }
        player.evaluateJavaScript("window.yootubeSetPictureInPictureState?.('\(state)')", completionHandler: nil)
    }

    private func finishWebPictureInPicture(_ playback: WebPlaybackState, message: String? = nil) {
        guard active else { return }
        let payload: [String: Any] = [
            "state": playback.dictionary,
            "message": message ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        player.evaluateJavaScript("window.yootubeFinishPictureInPicture?.(\(json))", completionHandler: nil)
    }

    private func recordPlaybackIfReady() {
        guard played, !recorded, let metadata else { return }
        recorded = true
        history.record(id: route.id, title: metadata.title)
    }

}

func nextAutoplayURL(currentVideoID: String,
                     recommendedVideos: [RecommendedVideo]?) -> URL? {
    recommendedVideos?.first {
        $0.videoId != currentVideoID && $0.url != nil
    }?.url
}

private struct WebPlaybackState {
    let currentTime: Double
    let shouldPlay: Bool
    let muted: Bool
    let volume: Double
    let playbackRate: Double

    init?(_ value: Any?) {
        guard let values = value as? [String: Any],
              let currentTime = (values["currentTime"] as? NSNumber)?.doubleValue,
              let shouldPlay = (values["shouldPlay"] as? NSNumber)?.boolValue,
              let muted = (values["muted"] as? NSNumber)?.boolValue,
              let volume = (values["volume"] as? NSNumber)?.doubleValue,
              let playbackRate = (values["playbackRate"] as? NSNumber)?.doubleValue,
              currentTime.isFinite, currentTime >= 0,
              volume.isFinite, (0...1).contains(volume),
              playbackRate.isFinite, (0.25...4).contains(playbackRate) else { return nil }
        self.currentTime = currentTime
        self.shouldPlay = shouldPlay
        self.muted = muted
        self.volume = volume
        self.playbackRate = playbackRate
    }

    init(currentTime: Double, shouldPlay: Bool, muted: Bool,
         volume: Double, playbackRate: Double) {
        self.currentTime = currentTime
        self.shouldPlay = shouldPlay
        self.muted = muted
        self.volume = volume
        self.playbackRate = playbackRate
    }

    var dictionary: [String: Any] {
        [
            "currentTime": currentTime,
            "shouldPlay": shouldPlay,
            "muted": muted,
            "volume": volume,
            "playbackRate": playbackRate
        ]
    }
}

struct PictureInPicturePlaybackIntent {
    private(set) var shouldPlay: Bool
    private var consecutivePausedSamples = 0

    init(shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
    }

    mutating func observe(_ status: AVPlayer.TimeControlStatus) {
        if status == .paused {
            consecutivePausedSamples += 1
            if consecutivePausedSamples >= 3 { shouldPlay = false }
        } else {
            consecutivePausedSamples = 0
            shouldPlay = true
        }
    }
}

@MainActor
private final class NativePictureInPictureSession: NSObject, @preconcurrency AVPictureInPictureControllerDelegate {
    private let player = AVPlayer()
    private let playerLayer: AVPlayerLayer
    private let controller: AVPictureInPictureController?
    private let initialPlayback: WebPlaybackState
    private let onStarted: () -> Void
    private let onStopped: (WebPlaybackState) -> Void
    private let onFailed: (String) -> Void
    private var startTask: Task<Void, Never>?
    private var playbackIntentTask: Task<Void, Never>?
    private var finished = false
    private var playbackIntent: PictureInPicturePlaybackIntent
    private var shouldPlayAtWillStop: Bool?

    init(sourceURL: URL, playerLayer: AVPlayerLayer, playback: WebPlaybackState,
         onStarted: @escaping () -> Void,
         onStopped: @escaping (WebPlaybackState) -> Void,
         onFailed: @escaping (String) -> Void) {
        self.playerLayer = playerLayer
        self.initialPlayback = playback
        self.onStarted = onStarted
        self.onStopped = onStopped
        self.onFailed = onFailed
        self.playbackIntent = PictureInPicturePlaybackIntent(shouldPlay: playback.shouldPlay)
        player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
        playerLayer.player = player
        controller = AVPictureInPictureController(playerLayer: playerLayer)
        super.init()
        controller?.delegate = self
    }

    func start() {
        guard let controller else {
            fail(L10n.t("当前播放环境无法创建画中画窗口。"))
            return
        }
        let startTime = CMTime(seconds: initialPlayback.currentTime, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.defaultRate = Float(initialPlayback.playbackRate)
        player.volume = initialPlayback.shouldPlay && !initialPlayback.muted
            ? Float(initialPlayback.volume) : 0
        player.playImmediately(atRate: Float(initialPlayback.playbackRate))

        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<150 {
                guard !Task.isCancelled, !finished else { return }
                if let error = player.currentItem?.error {
                    fail(L10n.t("画中画视频加载失败：\(error.localizedDescription)"))
                    return
                }
                if controller.isPictureInPicturePossible {
                    controller.startPictureInPicture()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            fail(L10n.t("画中画启动超时，请稍后重试。"))
        }
    }

    func stop() {
        guard !finished else { return }
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        } else {
            finish(with: initialPlayback)
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        startTask?.cancel()
        playbackIntentTask?.cancel()
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        player.pause()
        playerLayer.player = nil
        controller?.delegate = nil
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard !finished else { return }
        startTask?.cancel()
        if initialPlayback.shouldPlay {
            player.volume = initialPlayback.muted ? 0 : Float(initialPlayback.volume)
        } else {
            player.pause()
            player.seek(to: CMTime(seconds: initialPlayback.currentTime, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            player.volume = initialPlayback.muted ? 0 : Float(initialPlayback.volume)
        }
        playbackIntentTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !finished {
                playbackIntent.observe(player.timeControlStatus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        onStarted()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        fail(L10n.t("画中画启动失败：\(error.localizedDescription)"))
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        shouldPlayAtWillStop = playbackIntent.shouldPlay
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        let seconds = player.currentTime().seconds
        let playback = WebPlaybackState(
            currentTime: seconds.isFinite && seconds >= 0 ? seconds : initialPlayback.currentTime,
            shouldPlay: shouldPlayAtWillStop ?? playbackIntent.shouldPlay,
            muted: initialPlayback.muted,
            volume: initialPlayback.volume,
            playbackRate: Double(player.defaultRate)
        )
        finish(with: playback)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    private func finish(with playback: WebPlaybackState) {
        guard !finished else { return }
        finished = true
        startTask?.cancel()
        playbackIntentTask?.cancel()
        player.pause()
        playerLayer.player = nil
        controller?.delegate = nil
        onStopped(playback)
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        startTask?.cancel()
        playbackIntentTask?.cancel()
        player.pause()
        playerLayer.player = nil
        controller?.delegate = nil
        onFailed(message)
    }
}

extension VideoDetailModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        guard active else { decisionHandler(.cancel); return }
        if videoCache.isPlayerPage(url, videoID: route.id) {
            decisionHandler(.allow)
            return
        }
        let base = LocalServiceManager.invidiousURL
        if action.targetFrame?.isMainFrame != false,
           url.scheme == base.scheme, url.host == base.host, url.port == base.port,
           VideoRoute(url)?.id != route.id {
            decisionHandler(.cancel)
            navigate(url)
            return
        }
        // The player cannot navigate out to another instance or a remote page.
        decisionHandler(url.scheme == base.scheme && url.host == base.host && url.port == base.port ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active else { return }
        playerLoading = false
        webView.evaluateJavaScript("window.yootubeSetTheaterMode?.(\(playerTheaterMode))", completionHandler: nil)
        webView.evaluateJavaScript("!!document.querySelector('video,audio')") { [weak self] result, _ in
            guard let self, self.active else { return }
            if result as? Bool != true { self.playerError = L10n.t("播放器暂时未就绪，请稍后重试。") }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handlePlayerError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handlePlayerError(error)
    }

    private func handlePlayerError(_ error: Error) {
        guard active, (error as NSError).code != NSURLErrorCancelled else { return }
        playerLoading = false
        playerError = L10n.t("播放器连接失败，请重试。")
    }
}

private final class DetailPlaybackObserver: NSObject, WKScriptMessageHandler {
    weak var owner: VideoDetailModel?
    init(owner: VideoDetailModel) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let owner, message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url,
              VideoRoute(url)?.id == owner.route.id || owner.videoCache.isPlayerPage(url, videoID: owner.route.id) else { return }
        let values = message.body as? [String: Any]
        guard let action = message.body as? String ?? values?["action"] as? String else { return }
        switch action {
        case "playing": owner.didPlay()
        case "ended": owner.didEndPlayback()
        case "aspectRatio":
            if let value = (values?["value"] as? NSNumber)?.doubleValue {
                owner.setPlayerAspectRatio(value)
            }
        case "displayCycle": owner.cycleDisplayMode()
        case "exitPlayerFullScreen": owner.exitPlayerFullScreen()
        case "theater": owner.setPlayerTheaterMode(true)
        case "standard": owner.setPlayerTheaterMode(false)
        case "pictureInPicture":
            if let playback = WebPlaybackState(values?["state"]) {
                owner.requestPictureInPicture(playback)
            }
        case "stopPictureInPicture": owner.stopPictureInPicture()
        default: break
        }
    }
}
