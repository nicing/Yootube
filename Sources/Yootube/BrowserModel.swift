import AppKit
import Combine
import WebKit

enum BrowserPageDirection: Equatable {
    case new
    case backward
    case forward
    case replace(URL)
}

struct BrowserPageChange: Equatable {
    let sequence: Int
    let url: URL?
    let direction: BrowserPageDirection
}

enum BrowserHistoryReplayAction: Equatable {
    case showCurrent
    case goBack
    case goForward
    case load

    static func resolve(target: URL, current: URL?, back: URL?, forward: URL?,
                        direction: BrowserHistoryReplayDirection) -> Self {
        if direction == .backward, back == target { return .goBack }
        if direction == .forward, forward == target { return .goForward }
        if current == target { return .showCurrent }
        return .load
    }
}

enum BrowserHistoryReplayDirection: Equatable {
    case backward
    case forward
}

enum PlaybackKeyboardShortcut {
    static func matches(_ event: NSEvent, firstResponder: NSResponder?) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.type == .keyDown,
              !event.isARepeat,
              event.charactersIgnoringModifiers == " ",
              event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
        return !(firstResponder is NSTextView || firstResponder is NSTextField || firstResponder is NSButton)
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var title = "Yootube"
    @Published private(set) var location = ""
    @Published private(set) var pageURL: URL?
    @Published private(set) var pageChange = BrowserPageChange(sequence: 0, url: nil, direction: .new)
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var showsHome = true
    @Published private(set) var videoDetail: VideoDetailModel?
    @Published private(set) var nativeRoute: NativePageRoute?
    let history = WatchHistory()

    private var observations: [NSKeyValueObservation] = []
    private var detailReturnsHome = true
    private var pageChangeSequence = 0
    private var pendingWebPageURL: URL?

    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.addUserScript(WKUserScript(source: KumoWebTheme.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController.add(PlaybackObserver(owner: self), name: "videoPlaying")
        configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('playing', function(event) {
            if (event.target.tagName !== 'VIDEO') return;
            const heading = document.querySelector('h1');
            window.webkit.messageHandlers.videoPlaying.postMessage({
                title: heading ? heading.textContent.trim() : document.title
            });
        }, true);
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsMagnification = true
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
        observe(view)
        return view
    }()

    override init() {
        super.init()
        _ = webView
        PlaybackKeyMonitor.shared.connect(self)
    }

    func loadHome(direction: BrowserPageDirection = .new) {
        videoDetail?.stop()
        videoDetail = nil
        webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => v.pause())", completionHandler: nil)
        webView.stopLoading()
        pendingWebPageURL = nil
        errorMessage = nil
        nativeRoute = nil
        showsHome = true
        publishPageChange(nil, direction: direction)
    }

    func reload() {
        if let videoDetail { videoDetail.reload(); return }
        errorMessage = nil
        if webView.url == nil {
            loadHome()
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func goBack() {
        if videoDetail != nil {
            videoDetail?.stop()
            videoDetail = nil
            showsHome = detailReturnsHome
            publishPageChange(detailReturnsHome ? nil : webView.url, direction: .backward)
            return
        }
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func navigate(_ input: String) {
        if let url = URLRouting.destination(for: input, instanceURL: instanceURL()) {
            load(url: url)
        }
    }

    func loadPage(_ url: URL, replayDirection: BrowserHistoryReplayDirection? = nil) {
        load(url: url, replayDirection: replayDirection)
    }

    private func load(url: URL, direction: BrowserPageDirection = .new,
                      replayDirection: BrowserHistoryReplayDirection? = nil) {
        if videoDetail == nil { detailReturnsHome = showsHome }
        videoDetail?.stop()
        videoDetail = nil
        nativeRoute = nil
        showsHome = false
        errorMessage = nil
        publishPageChange(url, direction: direction)
        if let route = VideoRoute(url) {
            pendingWebPageURL = nil
            webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => v.pause())", completionHandler: nil)
            webView.stopLoading()
            videoDetail = VideoDetailModel(route: route, history: history) { [weak self] nextURL in
                self?.load(url: nextURL)
            }
            return
        }
        if let route = NativePageRoute(url) {
            pendingWebPageURL = nil
            webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => v.pause())", completionHandler: nil)
            webView.stopLoading()
            nativeRoute = route
            return
        }
        pendingWebPageURL = url
        if let replayDirection {
            switch BrowserHistoryReplayAction.resolve(
                target: url,
                current: webView.url,
                back: webView.backForwardList.backItem?.url,
                forward: webView.backForwardList.forwardItem?.url,
                direction: replayDirection
            ) {
            case .showCurrent:
                pendingWebPageURL = nil
                return
            case .goBack:
                webView.goBack()
                return
            case .goForward:
                webView.goForward()
                return
            case .load:
                break
            }
        }
        webView.load(URLRequest(url: url))
    }

    private func instanceURL() -> URL {
        LocalServiceManager.invidiousURL
    }

    private func isLocalServiceURL(_ url: URL) -> Bool {
        let local = instanceURL()
        return url.scheme == local.scheme && url.host == local.host && url.port == local.port
    }

    private func observe(_ view: WKWebView) {
        observations = [
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.title = view.title ?? "Yootube" }
            },
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.pageURL = view.url
                    self.location = view.url?.absoluteString ?? ""
                }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            }
        ]
    }

    private func publishPageChange(_ url: URL?, direction: BrowserPageDirection = .new) {
        pageURL = url
        location = url?.absoluteString ?? ""
        pageChangeSequence += 1
        pageChange = BrowserPageChange(sequence: pageChangeSequence, url: url, direction: direction)
    }
}

@MainActor
private final class PlaybackKeyMonitor {
    static let shared = PlaybackKeyMonitor()

    private weak var browser: BrowserModel?
    private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let detail = self?.browser?.videoDetail else { return event }
            let window = event.window ?? NSApp.keyWindow
            guard detail.player.window === window else { return event }
            let responder = window?.firstResponder
            if let view = responder as? NSView,
               view === detail.player || view.isDescendant(of: detail.player) {
                return event
            }
            guard PlaybackKeyboardShortcut.matches(event, firstResponder: responder) else { return event }
            detail.togglePlayback()
            return nil
        }
    }

    func connect(_ browser: BrowserModel) {
        self.browser = browser
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation?
    ) {
        errorMessage = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let requestedURL = pendingWebPageURL else { return }
        pendingWebPageURL = nil
        guard let finalURL = webView.url else { return }
        if finalURL != requestedURL {
            publishPageChange(finalURL, direction: .replace(requestedURL))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        guard let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }

        let pageDirection: BrowserPageDirection
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        if isMainFrame,
           navigationAction.navigationType == .backForward {
            if webView.backForwardList.backItem?.url == url {
                pageDirection = .backward
            } else if webView.backForwardList.forwardItem?.url == url {
                pageDirection = .forward
            } else { pageDirection = .new }
        } else { pageDirection = .new }

        if navigationAction.targetFrame?.isMainFrame != false,
           let local = URLRouting.youtubeDestination(for: url.absoluteString, instanceURL: instanceURL()) {
            decisionHandler(.cancel)
            load(url: local, direction: pageDirection)
            return
        }
        if isLocalServiceURL(url), url.path == "/" {
            decisionHandler(.cancel)
            loadHome(direction: pageDirection)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false, VideoRoute(url) != nil {
            decisionHandler(.cancel)
            load(url: url, direction: pageDirection)
            return
        }
        if isMainFrame, NativePageRoute(url) != nil {
            decisionHandler(.cancel)
            load(url: url, direction: pageDirection)
            return
        }

        if isMainFrame, ["http", "https"].contains(scheme), !isLocalServiceURL(url) {
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        if ["http", "https", "about", "javascript", "blob"].contains(scheme) {
            if isMainFrame, pendingWebPageURL != url,
               navigationAction.navigationType != .other || pendingWebPageURL == nil {
                pendingWebPageURL = url
                publishPageChange(url, direction: pageDirection)
            }
            decisionHandler(.allow)
            return
        }

        if scheme == "mailto", navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.cancel)
    }

    private func handleNavigationError(_ error: Error) {
        let navigationError = error as NSError
        guard !(navigationError.domain == NSURLErrorDomain && navigationError.code == NSURLErrorCancelled) else {
            return
        }
        pendingWebPageURL = nil
        errorMessage = error.localizedDescription
    }
}

private final class PlaybackObserver: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserModel?

    init(owner: BrowserModel) { self.owner = owner }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let owner, message.frameInfo.isMainFrame, !owner.showsHome,
              let url = message.frameInfo.request.url,
              url.host == LocalServiceManager.invidiousURL.host,
              url.port == LocalServiceManager.invidiousURL.port,
              ["/watch", "/embed"].contains(url.path) || url.path.hasPrefix("/embed/"),
              let local = URLRouting.youtubeDestination(
                for: "https://www.youtube.com" + url.path + (url.query.map { "?" + $0 } ?? ""),
                instanceURL: LocalServiceManager.invidiousURL),
              let id = URLComponents(url: local, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
              let body = message.body as? [String: String], let title = body["title"], !title.isEmpty else { return }
        owner.history.record(id: id, title: title.replacingOccurrences(of: " - Invidious", with: ""))
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
