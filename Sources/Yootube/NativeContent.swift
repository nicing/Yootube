import SwiftUI

let nativeVideoCardColumns = [
    GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18, alignment: .top)
]

enum NativePageRoute: Hashable, Identifiable {
    case search(SearchPageRoute)
    case channel(ChannelPageRoute)
    case playlist(PlaylistImportRoute)

    var id: String {
        switch self {
        case .search(let route): "search:\(route.query):\(route.page)"
        case .channel(let route): "channel:\(route.sourceURL.absoluteString)"
        case .playlist(let route): "\(route.sourceID):\(route.continuation ?? "")"
        }
    }

    init?(_ url: URL) {
        let base = LocalServiceManager.invidiousURL
        guard url.scheme == base.scheme, url.host == base.host, url.port == base.port else { return nil }
        if let route = SearchPageRoute(url) {
            self = .search(route)
        } else if let route = PlaylistImportRoute(url) {
            self = .playlist(route)
        } else if let route = ChannelPageRoute(url) {
            self = .channel(route)
        } else {
            return nil
        }
    }
}

struct SearchPageRoute: Hashable {
    let query: String
    let page: Int

    init?(_ url: URL) {
        guard url.path == "/search",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = parts.queryItems?.first(where: { $0.name == "q" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else { return nil }
        self.query = query
        self.page = max(1, Int(parts.queryItems?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1)
    }
}

struct ChannelPageRoute: Hashable {
    let sourceURL: URL
    let channelID: String?

    init?(_ url: URL) {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        if first == "channel", parts.count >= 2 {
            sourceURL = url
            channelID = parts[1]
        } else if ["user", "c"].contains(first), parts.count >= 2 {
            sourceURL = url
            channelID = nil
        } else if first.hasPrefix("@"), first.count > 1 {
            sourceURL = url
            channelID = nil
        } else {
            return nil
        }
    }

    var youtubeURL: URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "www.youtube.com"
        parts.path = sourceURL.path
        parts.query = sourceURL.query
        return parts.url
    }
}

struct NativeImageSource: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

struct NativeVideo: Decodable, Identifiable {
    let videoId: String
    let title: String
    let author: String?
    let authorId: String?
    let viewCount: Int?
    let viewCountText: String?
    let published: Int?
    let publishedText: String?
    let lengthSeconds: Int?
    var id: String { videoId }
}

struct NativeSearchResult: Decodable, Identifiable {
    let type: String
    let videoId: String?
    let playlistId: String?
    let title: String?
    let author: String?
    let authorId: String?
    let authorThumbnails: [NativeImageSource]?
    let playlistThumbnail: String?
    let description: String?
    let subCount: Int?
    let videoCount: Int?
    let viewCount: Int?
    let viewCountText: String?
    let publishedText: String?
    let lengthSeconds: Int?

    var id: String {
        "\(type):\(videoId ?? playlistId ?? authorId ?? "\(title ?? "unknown"):\(author ?? "")")"
    }

    var kind: SearchResultKind? { SearchResultKind(rawValue: type) }
}

enum SearchResultKind: String, CaseIterable, Identifiable {
    case video, channel, playlist
    var id: String { rawValue }
    var title: String {
        switch self { case .video: L10n.t("视频"); case .channel: L10n.t("频道"); case .playlist: L10n.t("播放列表") }
    }
}

struct NativeChannel: Decodable {
    let author: String
    let authorId: String
    let authorVerified: Bool?
    let authorBanners: [NativeImageSource]?
    let authorThumbnails: [NativeImageSource]?
    let subCount: Int?
    let totalViews: Int?
    let description: String?
    let latestVideos: [NativeVideo]
}

private struct ResolvedChannel: Decodable {
    let ucid: String?
    let browseId: String?
}

@MainActor
final class NativePageModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    let route: NativePageRoute
    @Published private(set) var phase = Phase.idle
    @Published private(set) var searchResults: [NativeSearchResult] = []
    @Published private(set) var channel: NativeChannel?
    @Published private(set) var playlist: PlaylistImport?
    @Published private(set) var loadingMore = false
    @Published private(set) var canLoadMore = false
    private var nextSearchPage = 1

    init(route: NativePageRoute) { self.route = route }

    func load() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            switch route {
            case .search(let route):
                let results = try await search(query: route.query, page: route.page)
                searchResults = results
                nextSearchPage = route.page + 1
                canLoadMore = !results.isEmpty
            case .channel(let route):
                let id = try await channelID(for: route)
                channel = try await VideoAPI.fetch(NativeChannel.self, path: "api/v1/channels/\(id)")
            case .playlist(let route):
                playlist = try await PlaylistImportAPI.fetch(route)
            }
            phase = .loaded
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retry() {
        phase = .idle
        Task { await load() }
    }

    func loadMoreSearchResults() {
        guard case .search(let route) = route, !loadingMore, canLoadMore else { return }
        loadingMore = true
        Task {
            defer { loadingMore = false }
            do {
                let results = try await search(query: route.query, page: nextSearchPage)
                let known = Set(searchResults.map(\.id))
                let additions = results.filter { !known.contains($0.id) }
                searchResults.append(contentsOf: additions)
                nextSearchPage += 1
                canLoadMore = !results.isEmpty && !additions.isEmpty
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func search(query: String, page: Int) async throws -> [NativeSearchResult] {
        try await VideoAPI.fetch([NativeSearchResult].self, path: "api/v1/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    private func channelID(for route: ChannelPageRoute) async throws -> String {
        if let id = route.channelID, !id.isEmpty { return id }
        guard let source = route.youtubeURL else { throw NativePageError.invalidChannel }
        let resolved = try await VideoAPI.fetch(ResolvedChannel.self, path: "api/v1/resolveurl", query: [
            URLQueryItem(name: "url", value: source.absoluteString)
        ])
        guard let id = resolved.ucid ?? resolved.browseId, !id.isEmpty else {
            throw NativePageError.invalidChannel
        }
        return id
    }
}

private enum NativePageError: LocalizedError {
    case invalidChannel
    var errorDescription: String? { L10n.t("无法识别这个频道。") }
}

struct NativeContentView: View {
    @StateObject private var model: NativePageModel
    @ObservedObject private var favorites: FavoritesStore
    @ObservedObject private var subscriptions: ChannelSubscriptionStore
    let navigate: (String) -> Void
    let didSavePlaylist: (UUID) -> Void
    @State private var searchFilter: SearchResultKind?

    init(route: NativePageRoute, favorites: FavoritesStore, subscriptions: ChannelSubscriptionStore,
         navigate: @escaping (String) -> Void,
         didSavePlaylist: @escaping (UUID) -> Void) {
        _model = StateObject(wrappedValue: NativePageModel(route: route))
        self.favorites = favorites
        self.subscriptions = subscriptions
        self.navigate = navigate
        self.didSavePlaylist = didSavePlaylist
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                loadingContent
            case .failed(let message):
                NativePageFailure(message: message, retry: model.retry)
            case .loaded:
                loadedContent
            }
        }
        .background(KumoTheme.canvas)
        .task { await model.load() }
    }

    private var loadingTitle: String {
        switch model.route {
        case .search: L10n.t("正在搜索…")
        case .channel: L10n.t("正在加载频道…")
        case .playlist: L10n.t("正在加载播放列表…")
        }
    }

    @ViewBuilder
    private var loadingContent: some View {
        switch model.route {
        case .channel:
            ChannelPageSkeleton()
        case .search, .playlist:
            ProgressView(loadingTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch model.route {
        case .search(let route): searchPage(route)
        case .channel: channelPage
        case .playlist(let route): playlistPage(route)
        }
    }

    private func searchPage(_ route: SearchPageRoute) -> some View {
        NativePageScroll {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.t("搜索结果")).font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                        Text("“\(route.query)”").font(.callout).foregroundStyle(KumoTheme.subtle)
                    }
                    Spacer()
                    SearchFilterPicker(selection: $searchFilter)
                }
                let results = filteredSearchResults
                if results.isEmpty {
                    NativeEmptyState(icon: "magnifying-glass", title: L10n.t("没有找到结果"),
                                     detail: L10n.t("试试更简短或不同的关键词。"))
                } else {
                    LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 22) {
                        ForEach(results) { result in searchCard(result) }
                    }
                    if searchFilter == nil, model.canLoadMore {
                        HStack {
                            Spacer()
                            Button {
                                model.loadMoreSearchResults()
                            } label: {
                                if model.loadingMore { ProgressView().controlSize(.small) }
                                else { Text(L10n.t("加载更多")) }
                            }
                            .buttonStyle(KumoButtonStyle())
                            .disabled(model.loadingMore)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var filteredSearchResults: [NativeSearchResult] {
        model.searchResults.filter { result in
            guard let kind = result.kind else { return false }
            return searchFilter == nil || searchFilter == kind
        }
    }

    @ViewBuilder
    private func searchCard(_ result: NativeSearchResult) -> some View {
        switch result.kind {
        case .video:
            if let id = result.videoId, let title = result.title {
                NativeVideoCard(videoID: id, title: title, author: result.author,
                                authorID: result.authorId,
                                metadata: videoMetadata(views: result.viewCountText,
                                                        count: result.viewCount,
                                                        published: result.publishedText),
                                lengthSeconds: result.lengthSeconds,
                                openVideo: { openVideo(id) },
                                openChannel: { openChannel($0) })
            }
        case .channel:
            if let id = result.authorId, let name = result.author {
                NativeChannelCard(name: name, channelID: id,
                                  avatar: VideoAPI.imageURL(result.authorThumbnails?.last?.url),
                                  subscribers: result.subCount,
                                  description: result.description,
                                  open: { openChannel(id) })
            }
        case .playlist:
            if let id = result.playlistId, let title = result.title {
                NativePlaylistCard(title: title, author: result.author,
                                   videoCount: result.videoCount,
                                   thumbnailURL: playlistThumbnailURL(result.playlistThumbnail),
                                   open: { openPlaylist(id) })
            }
        case nil:
            EmptyView()
        }
    }

    private var channelPage: some View {
        NativePageScroll {
            if let channel = model.channel {
                VStack(alignment: .leading, spacing: 24) {
                    ChannelHeader(channel: channel,
                                  subscribed: subscriptions.contains(channel.authorId),
                                  subscriptionAvailable: subscriptions.isLoaded) {
                        subscriptions.toggle(channel)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.t("视频")).font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Text(L10n.t("\(channel.latestVideos.count) 个最新视频"))
                            .font(.caption).foregroundStyle(KumoTheme.subtle)
                    }
                    if channel.latestVideos.isEmpty {
                        NativeEmptyState(icon: "video-camera", title: L10n.t("暂无视频"), detail: nil)
                    } else {
                        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 22) {
                            ForEach(channel.latestVideos) { video in
                                NativeVideoCard(videoID: video.videoId, title: video.title,
                                                author: nil, authorID: nil,
                                                metadata: videoMetadata(views: video.viewCountText,
                                                                        count: video.viewCount,
                                                                        published: video.publishedText),
                                                lengthSeconds: video.lengthSeconds,
                                                favoriteAuthor: channel.author,
                                                openVideo: { openVideo(video.videoId) },
                                                openChannel: { _ in })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func playlistPage(_ route: PlaylistImportRoute) -> some View {
        NativePageScroll {
            if let playlist = model.playlist {
                VStack(alignment: .leading, spacing: 24) {
                    PlaylistHeader(playlist: playlist, favorites: favorites) {
                        if let id = favorites.savePlaylist(sourceID: route.sourceID,
                                                           named: playlist.title,
                                                           videos: playlist.videos) {
                            didSavePlaylist(id)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.t("视频")).font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Text(L10n.t("\(playlist.items.count) 个视频"))
                            .font(.caption).foregroundStyle(KumoTheme.subtle)
                    }
                    if playlist.items.isEmpty {
                        NativeEmptyState(icon: "video-camera", title: L10n.t("播放列表中没有视频"), detail: nil)
                    } else {
                        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 22) {
                            ForEach(playlist.items) { item in
                                NativeVideoCard(videoID: item.videoID, title: item.title,
                                                author: item.author.isEmpty ? playlist.author : item.author,
                                                authorID: nil, metadata: nil,
                                                lengthSeconds: item.lengthSeconds,
                                                openVideo: { openPlaylistVideo(item, route: route) },
                                                openChannel: { _ in })
                            }
                        }
                    }
                }
            }
        }
    }

    private var cardColumns: [GridItem] {
        nativeVideoCardColumns
    }

    private func openVideo(_ id: String) {
        if let url = VideoRoute.watchURL(id: id) { navigate(url.absoluteString) }
    }

    private func openPlaylistVideo(_ item: PlaylistVideoItem, route: PlaylistImportRoute) {
        guard var parts = URLComponents(url: LocalServiceManager.invidiousURL.appendingPathComponent("watch"),
                                        resolvingAgainstBaseURL: false) else { return }
        parts.queryItems = [URLQueryItem(name: "v", value: item.videoID),
                            URLQueryItem(name: "list", value: route.id)]
        if let index = item.index { parts.queryItems?.append(URLQueryItem(name: "index", value: String(index))) }
        if let url = parts.url { navigate(url.absoluteString) }
    }

    private func openChannel(_ id: String) {
        guard !id.isEmpty else { return }
        navigate(LocalServiceManager.invidiousURL.appendingPathComponent("channel")
            .appendingPathComponent(id).absoluteString)
    }

    private func openPlaylist(_ id: String) {
        guard var parts = URLComponents(url: LocalServiceManager.invidiousURL.appendingPathComponent("playlist"),
                                        resolvingAgainstBaseURL: false) else { return }
        parts.queryItems = [URLQueryItem(name: "list", value: id)]
        if let url = parts.url { navigate(url.absoluteString) }
    }

    private func playlistThumbnailURL(_ source: String?) -> URL? {
        guard let source, let parts = URLComponents(string: source) else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        guard let marker = path.firstIndex(of: "vi"), path.indices.contains(marker + 1) else { return nil }
        return VideoAPI.thumbnailURL(path[marker + 1])
    }

    private func videoMetadata(views: String?, count: Int?, published: String?) -> String? {
        var values: [String] = []
        if let views, !views.isEmpty { values.append(views) }
        else if let count { values.append(L10n.t("\(count.formatted()) 次观看")) }
        if let published, !published.isEmpty { values.append(published) }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

private struct NativePageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(width: max(0, geometry.size.width - 56), alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 60)
            }
        }
    }
}

private struct SearchFilterPicker: View {
    @Binding var selection: SearchResultKind?
    var body: some View {
        HStack(spacing: 8) {
            filterButton(L10n.t("全部"), value: nil)
            ForEach(SearchResultKind.allCases) { kind in filterButton(kind.title, value: kind) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KumoTheme.recessed, in: RoundedRectangle(cornerRadius: 12))
    }

    private func filterButton(_ title: String, value: SearchResultKind?) -> some View {
        Button(title) { selection = value }
            .buttonStyle(KumoButtonStyle(variant: selection == value ? .secondary : .ghost,
                                         horizontalPadding: 12))
            .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

private struct ChannelHeader: View {
    let channel: NativeChannel
    let subscribed: Bool
    let subscriptionAvailable: Bool
    let toggleSubscription: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ChannelBanner(url: VideoAPI.imageURL(channel.authorBanners?.first?.url))
            HStack(alignment: .top, spacing: 18) {
                NativeRemoteImage(url: VideoAPI.imageURL(channel.authorThumbnails?.last?.url), icon: "user")
                    .frame(width: 88, height: 88)
                    .nativeImageBorder(Circle())
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Text(channel.author).font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                        if channel.authorVerified == true {
                            KumoIcon("check-circle", size: 16).foregroundStyle(KumoTheme.subtle)
                        }
                    }
                    HStack(spacing: 12) {
                        if let count = channel.subCount { Text(L10n.t("\(count.formatted()) 位订阅者")) }
                        if let views = channel.totalViews { Text(L10n.t("\(views.formatted()) 次观看")) }
                    }
                    .font(.caption).foregroundStyle(KumoTheme.subtle)
                    if let description = channel.description, !description.isEmpty {
                        Text(description).font(.callout).foregroundStyle(KumoTheme.text)
                            .lineLimit(4).lineSpacing(3).textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
                Button(action: toggleSubscription) {
                    KumoLabel(subscribed ? L10n.t("已订阅") : L10n.t("订阅"), icon: subscribed ? "check" : "bell")
                }
                .buttonStyle(KumoButtonStyle(variant: subscribed ? .secondary : .primary))
                .disabled(!subscriptionAvailable)
                .help(subscribed ? L10n.t("取消订阅") : L10n.t("订阅并保存到本机"))
                .accessibilityLabel(subscribed ? L10n.t("取消订阅 \(channel.author)") : L10n.t("订阅 \(channel.author)"))
            }
        }
    }
}

private struct ChannelPageSkeleton: View {
    var body: some View {
        NativePageScroll {
            SkeletonGroup {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        SkeletonBlock(radius: KumoTheme.radius)
                            .aspectRatio(6, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                        HStack(alignment: .top, spacing: 18) {
                            SkeletonBlock(radius: 44)
                                .frame(width: 88, height: 88)
                            VStack(alignment: .leading, spacing: 9) {
                                SkeletonBlock(radius: 5).frame(width: 220, height: 26)
                                SkeletonBlock(radius: 4).frame(width: 180, height: 11)
                                SkeletonBlock(radius: 4).frame(maxWidth: .infinity).frame(height: 12)
                                SkeletonBlock(radius: 4).frame(width: 320, height: 12)
                            }
                            Spacer(minLength: 0)
                            SkeletonBlock(radius: KumoTheme.radius).frame(width: 88, height: 36)
                        }
                    }
                    HStack {
                        SkeletonBlock(radius: 5).frame(width: 52, height: 20)
                        Spacer()
                        SkeletonBlock(radius: 4).frame(width: 112, height: 11)
                    }
                    LazyVGrid(columns: nativeVideoCardColumns, alignment: .leading, spacing: 22) {
                        ForEach(0..<8, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 10) {
                                SkeletonBlock(radius: KumoTheme.radiusSmall)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                SkeletonBlock(radius: 4)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 14)
                                SkeletonBlock(radius: 4)
                                    .frame(width: index.isMultiple(of: 3) ? 126 : 172, height: 11)
                            }
                            .padding(10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("正在加载频道"))
    }
}

private struct ChannelBanner: View {
    let url: URL?

    var body: some View {
        Color.clear
            .aspectRatio(6, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 220)
            .overlay {
                NativeRemoteImage(url: url, icon: "video-camera")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .nativeImageBorder(RoundedRectangle(cornerRadius: KumoTheme.radius))
    }
}

private struct PlaylistHeader: View {
    let playlist: PlaylistImport
    @ObservedObject var favorites: FavoritesStore
    let save: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            NativeRemoteImage(url: playlist.items.first.map { VideoAPI.thumbnailURL($0.videoID) }, icon: "play")
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: 300).clipped()
                .nativeImageBorder(RoundedRectangle(cornerRadius: KumoTheme.radius))
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("播放列表")).font(.caption).foregroundStyle(KumoTheme.subtle)
                Text(playlist.title).font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let author = playlist.author, !author.isEmpty {
                    Text(author).font(.system(size: 14, weight: .medium))
                }
                HStack(spacing: 12) {
                    if let count = playlist.videoCount { Text(L10n.t("\(count) 个视频")) }
                    if let views = playlist.viewCount { Text(L10n.t("\(views.formatted()) 次观看")) }
                }
                .font(.caption).foregroundStyle(KumoTheme.subtle)
                if let description = playlist.description, !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(KumoTheme.subtle).lineLimit(3)
                }
                Button(action: save) { KumoLabel(L10n.t("保存到本地收藏夹"), icon: "bookmark-simple") }
                    .buttonStyle(KumoButtonStyle(variant: .primary))
                    .disabled(!favorites.isLoaded || playlist.videos.isEmpty)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

struct NativeVideoCard: View {
    let videoID: String
    let title: String
    let author: String?
    let authorID: String?
    let metadata: String?
    let lengthSeconds: Int?
    var favoriteAuthor: String? = nil
    var thumbnailAvailable = true
    var relativeDate: Date? = nil
    var removeAction: (() -> Void)? = nil
    var removeAccessibilityLabel: String? = nil
    let openVideo: () -> Void
    let openChannel: (String) -> Void

    var body: some View {
        NativeCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: openVideo) {
                    NativeThumbnail(url: thumbnailAvailable ? VideoAPI.thumbnailURL(videoID) : nil,
                                    lengthSeconds: lengthSeconds)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button(action: openVideo) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(KumoTheme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if let author, !author.isEmpty {
                    if let authorID, !authorID.isEmpty {
                        Button(author) { openChannel(authorID) }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(KumoTheme.subtle).lineLimit(1)
                    } else {
                        Text(author).font(.caption).foregroundStyle(KumoTheme.subtle).lineLimit(1)
                    }
                }
                if metadata != nil || relativeDate != nil || removeAction != nil {
                    HStack(spacing: 6) {
                        if let metadata {
                            Text(metadata).lineLimit(1)
                        } else if let relativeDate {
                            Text(relativeDate, style: .relative).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let removeAction {
                            Button(action: removeAction) {
                                KumoIcon("minus-circle", size: 15)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("从此收藏夹移除"))
                            .accessibilityLabel(removeAccessibilityLabel ?? L10n.t("从此收藏夹移除"))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(KumoTheme.subtle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onDrag {
            YootubeDragPayload.video(id: videoID, title: title,
                                     author: favoriteAuthor ?? author).itemProvider()
        } preview: {
            YootubeVideoDragPreview(title: title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(L10n.t("可拖到左侧收藏夹"))
    }
}

private struct NativeChannelCard: View {
    let name: String
    let channelID: String
    let avatar: URL?
    let subscribers: Int?
    let description: String?
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            NativeCardSurface {
                VStack(alignment: .leading, spacing: 11) {
                    NativeRemoteImage(url: avatar, icon: "user")
                        .frame(width: 72, height: 72)
                        .nativeImageBorder(Circle())
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(KumoTheme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let subscribers {
                        Text(L10n.t("\(subscribers.formatted()) 位订阅者")).font(.caption).foregroundStyle(KumoTheme.subtle)
                    }
                    if let description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(KumoTheme.subtle)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("打开频道 \(name)"))
    }
}

private struct NativePlaylistCard: View {
    let title: String
    let author: String?
    let videoCount: Int?
    let thumbnailURL: URL?
    let open: () -> Void
    var body: some View {
        NativeCardSurface {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    NativeThumbnail(url: thumbnailURL, lengthSeconds: nil)
                        .overlay(alignment: .bottomTrailing) {
                            if let videoCount {
                                Text(L10n.t("\(videoCount) 个视频")).font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(KumoTheme.bodyOnDark).padding(.horizontal, 6).padding(.vertical, 4)
                                    .background(KumoTheme.surfaceBlack.opacity(0.82), in: RoundedRectangle(cornerRadius: 5)).padding(6)
                            }
                        }
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(KumoTheme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let author, !author.isEmpty {
                        Text(author).font(.caption).foregroundStyle(KumoTheme.subtle).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct NativeCardSurface<Content: View>: View {
    @State private var hovered = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? KumoTheme.tint.opacity(0.7) : .clear,
                        in: RoundedRectangle(cornerRadius: KumoTheme.radiusPanel))
            .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radiusPanel))
            .onHover { hovered = $0 }
    }
}

private struct NativeThumbnail: View {
    let url: URL?
    let lengthSeconds: Int?
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .overlay {
                NativeRemoteImage(url: url, icon: "play")
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
                .nativeImageBorder(RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                .overlay(alignment: .bottomTrailing) {
                    if let lengthSeconds {
                        Text(durationText(lengthSeconds)).font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(KumoTheme.bodyOnDark).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(KumoTheme.surfaceBlack.opacity(0.84), in: RoundedRectangle(cornerRadius: 4)).padding(5)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func durationText(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct NativeRemoteImage: View {
    let url: URL?
    let icon: String
    var body: some View {
        CachedAsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { KumoTheme.placeholder.overlay(KumoIcon(icon).foregroundStyle(KumoTheme.subtle)) }
        }
    }
}

private struct NativeImageBorder<BorderShape: InsettableShape>: ViewModifier {
    let shape: BorderShape

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(KumoTheme.line, lineWidth: 1))
    }
}

private extension View {
    func nativeImageBorder<BorderShape: InsettableShape>(_ shape: BorderShape) -> some View {
        modifier(NativeImageBorder(shape: shape))
    }
}

private struct NativeEmptyState: View {
    let icon: String
    let title: String
    let detail: String?
    var body: some View {
        VStack(spacing: 10) {
            KumoIcon(icon, size: 22).foregroundStyle(KumoTheme.subtle)
            Text(title).font(.system(size: 14, weight: .medium))
            if let detail { Text(detail).font(.caption).foregroundStyle(KumoTheme.subtle) }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct NativePageFailure: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            KumoIcon("video-camera", size: 22).foregroundStyle(KumoTheme.subtle)
            Text(L10n.t("页面暂时无法加载")).font(.headline)
            Text(L10n.t(message)).font(.callout).foregroundStyle(KumoTheme.subtle).multilineTextAlignment(.center)
            Button(L10n.t("重试"), action: retry).buttonStyle(KumoButtonStyle())
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
