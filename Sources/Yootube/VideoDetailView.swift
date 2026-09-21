import AVFoundation
import AppKit
import SwiftUI
import WebKit

private struct PlayerBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct VideoDetailView: View {
    @ObservedObject var model: VideoDetailModel
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var videoCache: VideoCacheStore
    @Binding var sidebarExpanded: Bool
    let navigate: (String) -> Void
    @State private var descriptionExpanded = false
    @State private var showsFavoritePicker = false
    @State private var showsCachePicker = false
    @State private var sidebarStateBeforeTheater: Bool?
    @State private var copiedVideoLink = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1080
            let contentPadding: CGFloat = 24
            let availableWidth = geometry.size.width - contentPadding * 2
            let contentWidth = model.playerTheaterMode ? availableWidth : min(availableWidth, 1440)
            let videoWidth = wide ? contentWidth - 336 : contentWidth
            let detailLayout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.playerTheaterMode {
                        playerPlaceholder(width: contentWidth)
                    }
                    detailLayout {
                        VStack(alignment: .leading, spacing: 22) {
                            if !model.playerTheaterMode {
                                playerPlaceholder(width: videoWidth)
                            }
                            detailSections
                        }
                        .frame(width: videoWidth, alignment: .leading)
                        recommendations
                            .frame(width: wide ? 308 : contentWidth, alignment: .leading)
                    }
                }
                .frame(width: contentWidth)
                .padding(.vertical, contentPadding)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .overlayPreferenceValue(PlayerBoundsKey.self) { anchor in
                GeometryReader { overlay in
                    if let anchor {
                        let rect = overlay[anchor]
                        // Keep one WKWebView mounted while resizing, so playback and focus survive.
                        player
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
            .clipped()
        }
        .background(KumoTheme.canvas)
        .onChange(of: model.playerTheaterMode) { _, enabled in
            updateSidebar(forTheaterMode: enabled)
        }
        .onChange(of: sidebarExpanded) { _, expanded in
            if model.playerTheaterMode && expanded {
                sidebarStateBeforeTheater = nil
                model.exitTheaterMode()
            }
        }
        .onDisappear {
            if let previous = sidebarStateBeforeTheater { sidebarExpanded = previous }
        }
        .sheet(isPresented: $showsFavoritePicker) {
            if let video = model.metadata {
                FavoritePicker(favorites: favorites, video: FavoriteVideo(
                    id: video.videoId, title: video.title, author: video.author, savedAt: Date()))
            }
        }
        .confirmationDialog(L10n.t("选择缓存清晰度"), isPresented: $showsCachePicker,
                            titleVisibility: .visible) {
            if let video = model.metadata {
                ForEach(video.cacheOptions) { option in
                    Button(cacheLabel(for: option)) { model.cache(option: option) }
                }
            }
            if videoCache.entry(for: model.route.id) != nil {
                Button(L10n.t("删除本地缓存"), role: .destructive) { model.removeCache() }
            }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t("选择要保存在此 Mac 的视频分辨率。"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .showVideoFavoritePicker)) { _ in
            if model.metadata != nil, favorites.isLoaded { showsFavoritePicker = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showVideoCachePicker)) { _ in
            guard let video = model.metadata,
                  !videoCache.isCaching(model.route.id),
                  !video.cacheOptions.isEmpty || videoCache.entry(for: model.route.id) != nil else { return }
            showsCachePicker = true
        }
        .alert(L10n.t("缓存视频"), isPresented: Binding(
            get: { model.cacheError != nil || videoCache.error(for: model.route.id) != nil },
            set: { if !$0 { model.dismissCacheError() } }
        )) {
            Button(L10n.t("好")) { model.dismissCacheError() }
        } message: {
            Text(L10n.t(model.cacheError ?? videoCache.error(for: model.route.id) ?? ""))
        }
    }

    private func playerPlaceholder(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: width / model.playerAspectRatio)
            .anchorPreference(key: PlayerBoundsKey.self, value: .bounds) { $0 }
    }

    @ViewBuilder
    private var detailSections: some View {
        if let metadata = model.metadata {
            details(metadata)
            comments
        } else if let error = model.error {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t(error)).foregroundStyle(KumoTheme.subtle)
                Button(L10n.t("重新加载详情")) { model.reload() }
                    .buttonStyle(KumoButtonStyle())
            }
        } else {
            VideoDetailsSkeleton()
        }
    }

    private func updateSidebar(forTheaterMode enabled: Bool) {
        if enabled {
            guard sidebarStateBeforeTheater == nil else { return }
            sidebarStateBeforeTheater = sidebarExpanded
            sidebarExpanded = false
        } else if let previous = sidebarStateBeforeTheater {
            sidebarStateBeforeTheater = nil
            sidebarExpanded = previous
        }
    }

    private var player: some View {
        EmbeddedPlayer(webView: model.player, loading: model.playerLoading,
                       error: model.playerError, retry: model.retryPlayback,
                       pictureInPictureLayer: model.pictureInPictureLayer)
    }

    private func details(_ video: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Text(video.title)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { copyYouTubeLink(video.videoId) } label: {
                    KumoIcon(copiedVideoLink ? "check" : "link-simple", size: 18)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedVideoLink ? KumoTheme.brand : KumoTheme.subtle)
                .help(copiedVideoLink ? L10n.t("已复制") : L10n.t("复制 YouTube 链接"))
                .accessibilityLabel(copiedVideoLink ? L10n.t("已复制 YouTube 链接") : L10n.t("复制 YouTube 链接"))
            }
            HStack(spacing: 12) {
                Button { openChannel(video) } label: {
                    CachedAsyncImage(url: VideoAPI.avatarURL(video.authorThumbnails?.first?.url)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(KumoTheme.placeholder).overlay(KumoIcon("user").foregroundStyle(KumoTheme.subtle))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("打开 \(video.author) 的频道"))
                .accessibilityLabel(L10n.t("打开 \(video.author) 的频道"))
                Button { openChannel(video) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.author).font(.system(size: 14, weight: .semibold))
                        if let subscribers = video.subCountText {
                            Text(L10n.t("\(subscribers) 位订阅者")).font(.caption).foregroundStyle(KumoTheme.subtle)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(L10n.t("打开 \(video.author) 的频道"))
                .accessibilityLabel(L10n.t("打开 \(video.author) 的频道"))
                Spacer(minLength: 8)
                Button { showsFavoritePicker = true } label: {
                    let isFavorite = favorites.contains(video.videoId)
                    HStack(spacing: 8) {
                        KumoIcon(isFavorite ? "bookmark-simple-fill" : "bookmark-simple")
                            .foregroundStyle(isFavorite ? KumoTheme.brand : KumoTheme.text)
                        Text(isFavorite ? L10n.t("已收藏") : L10n.t("收藏"))
                    }
                }
                .buttonStyle(KumoButtonStyle())
                .disabled(!favorites.isLoaded)
                .help(L10n.t("选择要保存到的收藏夹"))
                .accessibilityLabel(favorites.contains(video.videoId) ? L10n.t("编辑视频收藏") : L10n.t("收藏视频"))
                let cachedEntry = videoCache.entry(for: video.videoId)
                let caching = videoCache.isCaching(video.videoId)
                Menu {
                    if !video.cacheOptions.isEmpty {
                        Section(L10n.t("选择缓存清晰度")) {
                            ForEach(video.cacheOptions) { option in
                                Button(cacheLabel(for: option)) {
                                    model.cache(option: option)
                                }
                            }
                        }
                    }
                    if let cachedEntry {
                        Section {
                            Text(L10n.t("本地占用 \(cacheSizeText(cachedEntry.byteCount))"))
                            Button(L10n.t("删除本地缓存"), role: .destructive) { model.removeCache() }
                        }
                    }
                } label: {
                    if caching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t("缓存中…"))
                        }
                    } else if let cachedEntry {
                        KumoLabel(L10n.t("已缓存 \(cachedEntry.qualityHeight)p"), icon: "check-circle")
                    } else {
                        KumoLabel(L10n.t("缓存"), icon: "download-simple")
                    }
                }
                .buttonStyle(KumoButtonStyle())
                .disabled(caching || (video.cacheOptions.isEmpty && cachedEntry == nil))
                .help(cacheHelp(for: video, entry: cachedEntry))
                Button(L10n.t("频道与订阅")) {
                    openChannel(video)
                }
                .buttonStyle(KumoButtonStyle())
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    if let count = video.viewCount {
                        Text(L10n.t("\(count.formatted()) 次观看"))
                    }
                    if let date = video.publishedText { Text(date) }
                    Spacer(minLength: 0)
                    if let likes = video.likeCount {
                        KumoLabel(likes.formatted(), icon: "thumbs-up")
                    }
                }
                .font(.caption).foregroundStyle(KumoTheme.subtle)
                if let description = video.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .lineLimit(descriptionExpanded ? nil : 3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(descriptionExpanded ? L10n.t("收起简介") : L10n.t("展开简介")) {
                        descriptionExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minHeight: 40)
                }
            }
            .padding(18)
            .background(KumoTheme.recessed, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func openChannel(_ video: VideoMetadata) {
        navigate(LocalServiceManager.invidiousURL
            .appendingPathComponent("channel")
            .appendingPathComponent(video.authorId)
            .absoluteString)
    }

    private func copyYouTubeLink(_ videoID: String) {
        guard let url = VideoRoute.youtubeURL(id: videoID) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copiedVideoLink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedVideoLink = false
        }
    }

    private func cacheHelp(for video: VideoMetadata, entry: VideoCacheEntry?) -> String {
        if let entry { return L10n.t("已缓存 \(entry.qualityHeight)p，可更换清晰度或删除本地缓存") }
        guard !video.cacheOptions.isEmpty else { return L10n.t("当前视频没有可缓存的兼容格式") }
        return L10n.t("选择分辨率缓存到此 Mac，下次优先从本地播放")
    }

    private func cacheLabel(for option: VideoCacheOption) -> String {
        option.height >= 1080 ? L10n.t("\(option.height)p（高清，有声音）") : L10n.t("\(option.height)p（有声音）")
    }

    private func cacheSizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(L10n.t("接着看")).font(.system(size: 16, weight: .semibold))
                Spacer()
                Toggle(L10n.t("自动播放"), isOn: $model.autoplayEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 12))
            }
            if model.metadata == nil {
                RecommendationsSkeleton()
            } else if let videos = model.metadata?.recommendedVideos, !videos.isEmpty {
                ForEach(validRecommendations(videos)) { video in
                    Button {
                        if let url = video.url { navigate(url.absoluteString) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            CachedAsyncImage(url: LocalServiceManager.invidiousURL.appendingPathComponent("vi/\(video.videoId)/mqdefault.jpg")) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { KumoTheme.placeholder }
                            }
                            .frame(width: 128, height: 72)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomTrailing) {
                                if let duration = video.lengthSeconds {
                                    Text(durationText(duration))
                                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                                        .foregroundStyle(KumoTheme.bodyOnDark).padding(3)
                                        .background(KumoTheme.surfaceBlack.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                        .padding(4)
                                }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(video.title).font(.system(size: 12, weight: .medium)).lineLimit(3)
                                if let author = video.author { Text(author).font(.caption2).foregroundStyle(KumoTheme.subtle).lineLimit(1) }
                                if let views = video.viewCountText { Text(L10n.t("\(views) 次观看")).font(.caption2).foregroundStyle(KumoTheme.subtle) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onDrag {
                        YootubeDragPayload.video(id: video.videoId,
                                                 title: video.title,
                                                 author: video.author).itemProvider()
                    } preview: {
                        YootubeVideoDragPreview(title: video.title)
                    }
                    .accessibilityHint(L10n.t("可拖到左侧收藏夹"))
                }
            } else {
                Text(L10n.t("暂无相关推荐"))
                    .font(.callout).foregroundStyle(KumoTheme.subtle)
            }
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.t("评论")).font(.system(size: 16, weight: .semibold))
                Spacer()
                if !model.commentsLoaded && !model.commentsLoading {
                    Button(L10n.t("加载评论")) { model.loadComments() }.buttonStyle(KumoButtonStyle())
                }
            }
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(comment.author).font(.system(size: 12, weight: .semibold))
                        if let date = comment.publishedText { Text(date).font(.caption).foregroundStyle(KumoTheme.subtle) }
                    }
                    Text(comment.content).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    if let likes = comment.likeCount, likes > 0 {
                        KumoLabel(likes.formatted(), icon: "thumbs-up").font(.caption).foregroundStyle(KumoTheme.subtle)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.commentsLoaded && model.comments.isEmpty {
                Text(L10n.t("暂无评论")).font(.callout).foregroundStyle(KumoTheme.subtle)
            }
            if model.commentsLoading { ProgressView().controlSize(.small) }
            if let error = model.commentsError {
                HStack {
                    Text(L10n.t(error)).font(.caption).foregroundStyle(KumoTheme.subtle)
                    Button(L10n.t("重试")) { model.loadComments() }
                }
            } else if model.continuation != nil && !model.commentsLoading {
                Button(L10n.t("加载更多评论")) { model.loadComments() }.buttonStyle(KumoButtonStyle())
            }
        }
        .padding(.top, 6)
    }

    private func validRecommendations(_ videos: [RecommendedVideo]) -> [RecommendedVideo] {
        var ids = Set<String>()
        return videos.filter { $0.url != nil && ids.insert($0.id).inserted }
    }

    private func durationText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VideoDetailsSkeleton: View {
    var body: some View {
        SkeletonGroup {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    SkeletonBlock(radius: 6).frame(maxWidth: .infinity).frame(height: 25)
                    SkeletonBlock(radius: 5).frame(width: 260, height: 19)
                }
                HStack(spacing: 12) {
                    SkeletonBlock(radius: 21).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(radius: 4).frame(width: 132, height: 13)
                        SkeletonBlock(radius: 4).frame(width: 88, height: 10)
                    }
                    Spacer(minLength: 8)
                    SkeletonBlock(radius: 10).frame(width: 72, height: 36)
                    SkeletonBlock(radius: 10).frame(width: 92, height: 36)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(radius: 4).frame(width: 190, height: 10)
                    SkeletonBlock(radius: 4).frame(maxWidth: .infinity).frame(height: 11)
                    SkeletonBlock(radius: 4).frame(maxWidth: .infinity).frame(height: 11)
                    SkeletonBlock(radius: 4).frame(width: 220, height: 11)
                }
                .padding(18)
                .background(KumoTheme.recessed.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("正在加载视频详情"))
    }
}

private struct RecommendationsSkeleton: View {
    var body: some View {
        SkeletonGroup {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        SkeletonBlock(radius: KumoTheme.radiusSmall)
                            .frame(width: 128, height: 72)
                        VStack(alignment: .leading, spacing: 7) {
                            SkeletonBlock(radius: 4).frame(maxWidth: .infinity).frame(height: 12)
                            SkeletonBlock(radius: 4)
                                .frame(width: index == 1 ? 112 : 132, height: 12)
                            SkeletonBlock(radius: 4).frame(width: 82, height: 9)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("正在加载推荐视频"))
    }
}

struct SkeletonBlock: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(KumoTheme.skeleton)
    }
}

struct SkeletonGroup<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerAtEnd = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, highlight, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: max(90, geometry.size.width * 0.42))
                        .rotationEffect(.degrees(12))
                        .offset(x: shimmerAtEnd ? geometry.size.width + 120 : -geometry.size.width - 120)
                    }
                    .clipped()
                    .mask { content() }
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmerAtEnd = true
                }
            }
    }

    private var highlight: Color { KumoTheme.skeletonHighlight.opacity(0.82) }
}

private struct PlayerStatusView: View {
    let loading: Bool
    let error: String?
    let retry: () -> Void

    var body: some View {
        ZStack {
            if let error {
                VStack(spacing: 16) {
                    Text(L10n.t(error)).font(.callout)
                    Button(L10n.t("重试播放"), action: retry).buttonStyle(DetailButtonStyle())
                }
            } else if loading {
                ProgressView(L10n.t("正在准备播放…"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KumoTheme.surfaceBlack)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(KumoTheme.bodyOnDark)
    }
}

final class PlayerHostView: NSView {
    static let webContentBleed: CGFloat = 1

    let webView: WKWebView
    private let statusView: NSHostingView<PlayerStatusView>
    private let pictureInPictureLayer: AVPlayerLayer

    init(webView: WKWebView, pictureInPictureLayer: AVPlayerLayer = AVPlayerLayer()) {
        self.webView = webView
        self.pictureInPictureLayer = pictureInPictureLayer
        statusView = NSHostingView(rootView: PlayerStatusView(loading: true, error: nil, retry: {}))
        super.init(frame: .zero)
        // Keep video, controls and loading in one native clip, avoiding separate
        // SwiftUI and WebKit edge compositing.
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.insertSublayer(pictureInPictureLayer, at: 0)
        addSubview(webView)
        addSubview(statusView)
    }

    func updateStatus(loading: Bool, error: String?, retry: @escaping () -> Void) {
        statusView.rootView = PlayerStatusView(loading: loading, error: error, retry: retry)
        statusView.isHidden = !loading && error == nil
    }

    func restoreWebViewLayoutAfterFullScreen() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // Keep the independently composited WebKit video edge behind the one
        // native rounded clip. Coincident edges can round to different output
        // pixels when the window moves, producing a display-only dark seam.
        webView.frame = bounds.insetBy(dx: -Self.webContentBleed, dy: -Self.webContentBleed)
        statusView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureInPictureLayer.frame = bounds
        CATransaction.commit()
    }
}

struct EmbeddedPlayer: NSViewRepresentable {
    let webView: WKWebView
    let loading: Bool
    let error: String?
    let retry: () -> Void
    let pictureInPictureLayer: AVPlayerLayer

    init(webView: WKWebView, loading: Bool, error: String?, retry: @escaping () -> Void,
         pictureInPictureLayer: AVPlayerLayer = AVPlayerLayer()) {
        self.webView = webView
        self.loading = loading
        self.error = error
        self.retry = retry
        self.pictureInPictureLayer = pictureInPictureLayer
    }

    func makeNSView(context: Context) -> PlayerHostView {
        PlayerHostView(webView: webView, pictureInPictureLayer: pictureInPictureLayer)
    }
    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        nsView.updateStatus(loading: loading, error: error, retry: retry)
    }
}

private struct DetailButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(KumoTheme.bodyOnDark.opacity(configuration.isPressed ? 0.14 : 0.07), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    }
}
