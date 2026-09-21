import SwiftUI

private struct PendingPageLoad {
    let url: URL
    let replayDirection: BrowserHistoryReplayDirection?
}

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @StateObject private var browser = BrowserModel()
    @StateObject private var service = LocalServiceManager.shared
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var subscriptions = ChannelSubscriptionStore()
    @StateObject private var videoCache = VideoCacheStore.shared
    @StateObject private var toolbarTooltipController = ToolbarTooltipController()
    @State private var selectedFolderID: UUID?
    @State private var navigation = AppNavigationHistory()
    @State private var query = ""
    @State private var submittedYouTubeLinks: [URL: String] = [:]
    @State private var pendingPageLoad: PendingPageLoad?
    @State private var showsNewFolder = false
    @State private var showsKeyboardShortcuts = false
    @State private var commandKeyPressed = false
    @FocusState private var searchFocused: Bool
    @AppStorage("sidebarExpanded") private var sidebarExpanded = true

    private let canvas = KumoTheme.canvas

    var body: some View {
        HStack(spacing: 0) {
            if sidebarExpanded {
                FavoritesSidebar(favorites: favorites, selectedFolderID: selectedFolderID,
                                 isHome: isHome, showsShortcutHints: commandKeyPressed,
                                 selectFolder: selectFolder, goHome: goHome)
                    .zIndex(1)
            }
            mainContent
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.top, 8)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .padding(.leading, sidebarExpanded ? 0 : 8)
        }
        .background(KumoTheme.sidebar)
        .background {
            AppKeyboardShortcutMonitor(hasVideoDetail: browser.videoDetail != nil,
                                       modifierFlagsChanged: { flags in
                                           commandKeyPressed = flags.contains(.command)
                                       },
                                       outsideSearchClicked: resignSearchFieldEditor,
                                       action: handleKeyboardShortcut)
                .frame(width: 0, height: 0)
        }
        .foregroundStyle(KumoTheme.text)
        .tint(KumoTheme.brand)
        .buttonStyle(KumoButtonStyle())
        .toolbar { applicationToolbar }
        .onAppear { service.start() }
        .onDisappear { toolbarTooltipController.hide() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in sidebarExpanded.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            commandKeyPressed = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFavoriteFolder)) { _ in
            if favorites.isLoaded { showsNewFolder = true }
        }
        .onChange(of: service.state) { _, state in
            if state == .ready, let pending = pendingPageLoad {
                pendingPageLoad = nil
                browser.loadPage(pending.url, replayDirection: pending.replayDirection)
            }
        }
        .onChange(of: browser.pageChange) { _, change in
            synchronizeBrowserPage(change)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLocation)) { _ in
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .goHome)) { _ in goHome() }
        .onReceive(NotificationCenter.default.publisher(for: .localDataImported)) { _ in
            favorites.reload()
            subscriptions.reload()
            browser.history.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageDidChange)) { _ in
            browser.videoDetail?.updateLanguage()
        }
        .onChange(of: favorites.folders.map(\.id)) { _, ids in
            if let id = selectedFolderID, !ids.contains(id) { goHome() }
        }
        .sheet(isPresented: $showsNewFolder) {
            FolderNameSheet(favorites: favorites, didSave: selectFolder)
        }
        .sheet(isPresented: $showsKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .modifier(ContentErrorAlerts(favorites: favorites, subscriptions: subscriptions))
    }

    @ToolbarContentBuilder
    private var applicationToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                toolbarButton("sidebar-simple", label: sidebarExpanded ? L10n.t("收起侧栏") : L10n.t("展开侧栏"),
                              shortcut: "/", enabled: true, action: toggleSidebar)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) {
                toolbarNavigationAndSearch
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                toolbarButton("house", label: L10n.t("首页"), shortcut: "H", enabled: true, action: goHome)
                    .padding(.trailing, 8)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                toolbarButton("sidebar-simple", label: sidebarExpanded ? L10n.t("收起侧栏") : L10n.t("展开侧栏"),
                              shortcut: "/", enabled: true, action: toggleSidebar)
            }
            ToolbarItem(placement: .principal) {
                toolbarNavigationAndSearch
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarButton("house", label: L10n.t("首页"), shortcut: "H", enabled: true, action: goHome)
                    .padding(.trailing, 8)
            }
        }
    }

    private var toolbarNavigationAndSearch: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                toolbarButton("arrow-left", label: L10n.t("返回"), shortcut: "←",
                              enabled: canNavigateBack, action: toolbarGoBack)
                toolbarButton("arrow-right", label: L10n.t("前进"), shortcut: "→",
                              enabled: canNavigateForward, action: toolbarGoForward)
            }
            toolbarSearch
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottomLeading) {
            canvas
            if let id = selectedFolderID, let folder = favorites.folder(id) {
                ScrollView {
                    FavoritesList(favorites: favorites, folder: folder, available: service.state == .ready) { video in
                        openFavorite(video)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if browser.showsHome {
                home
            } else if service.state == .ready {
                if let detail = browser.videoDetail {
                    VideoDetailView(model: detail, favorites: favorites, videoCache: videoCache,
                                    sidebarExpanded: $sidebarExpanded,
                                    navigate: navigateFromDetail)
                        .id(detail.route.source)
                } else if let route = browser.nativeRoute {
                    NativeContentView(route: route, favorites: favorites, subscriptions: subscriptions,
                                      navigate: navigateFromDetail,
                                      didSavePlaylist: selectFolder)
                        .id(route.id)
                } else {
                    WebView(model: browser)
                }
            }

            if let error = browser.errorMessage, !browser.showsHome {
                VStack(spacing: 16) {
                    Text(L10n.t("页面暂时无法加载")).font(.headline)
                    Text(L10n.t(error)).font(.callout).foregroundStyle(KumoTheme.subtle)
                    HStack {
                        Button(L10n.t("重试")) { browser.reload() }
                        Button(L10n.t("返回首页"), action: goHome)
                    }
                }
                .padding(30)
                .background(canvas, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbarSearch: some View {
        HStack(spacing: 10) {
            KumoIcon("magnifying-glass", size: 17)
                .foregroundStyle(KumoTheme.subtle)
            TextField(L10n.t("搜索或粘贴 YouTube 链接"), text: $query,
                      prompt: Text(L10n.t("搜索或粘贴 YouTube 链接")).foregroundStyle(KumoTheme.subtle))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(KumoTheme.text)
                .focused($searchFocused)
                .onSubmit { submit(query) }
                .onChange(of: query) { previous, value in
                    if URLRouting.isBulkInsertion(from: previous, to: value),
                       URLRouting.youtubeDestination(for: value, instanceURL: LocalServiceManager.invidiousURL) != nil {
                        submit(value)
                    }
                }
            if pendingPageLoad != nil || serviceIsStarting {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 13)
        .frame(width: 420, height: 36)
        .background(KumoTheme.base, in: Capsule())
        .overlay(Capsule().strokeBorder(searchFocused ? KumoTheme.focus : KumoTheme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func toolbarButton(_ icon: String, label: String, shortcut: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        ToolbarIconButton(icon: icon, label: label, shortcut: shortcut, enabled: enabled,
                          tooltipController: toolbarTooltipController, action: action)
    }

    private func toggleSidebar() {
        sidebarExpanded.toggle()
    }

    private func focusSearch() {
        searchFocused = true
        if ToolbarSearchFieldLocator.focus(in: NSApp.keyWindow) { return }
        DispatchQueue.main.async {
            searchFocused = true
            _ = ToolbarSearchFieldLocator.focus(in: NSApp.keyWindow)
        }
    }

    private func handleKeyboardShortcut(_ shortcut: AppKeyboardShortcutAction) {
        switch shortcut {
        case .toggleSidebar:
            toggleSidebar()
        case .focusSearch:
            focusSearch()
        case .home:
            goHome()
        case .keyboardShortcuts:
            showsKeyboardShortcuts = true
        case .favoriteFolder(let index):
            guard favorites.folders.indices.contains(index) else { return }
            selectFolder(favorites.folders[index].id)
        case .lastFavoriteFolder:
            if let folder = favorites.folders.last { selectFolder(folder.id) }
        case .back:
            if canNavigateBack { toolbarGoBack() }
        case .forward:
            if canNavigateForward { toolbarGoForward() }
        case .newFavoriteFolder:
            if favorites.isLoaded { showsNewFolder = true }
        case .settings:
            openSettings()
        case .saveVideo:
            NotificationCenter.default.post(name: .showVideoFavoritePicker, object: nil)
        case .theaterMode:
            browser.videoDetail?.cycleDisplayMode()
        case .cacheVideo:
            NotificationCenter.default.post(name: .showVideoCachePicker, object: nil)
        case .muteVideo:
            browser.videoDetail?.toggleMute()
        case .captions:
            browser.videoDetail?.toggleCaptions()
        }
    }

    private var isHome: Bool { navigation.current == .home }

    private var serviceIsStarting: Bool {
        if case .starting = service.state { return true }
        return false
    }

    private var canNavigateBack: Bool {
        navigation.canGoBack
    }

    private var canNavigateForward: Bool {
        navigation.canGoForward
    }

    private var home: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        YouTubeLogo().frame(width: 52, height: 37)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Yootube")
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.6)
                            Text(homeSubtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(KumoTheme.subtle)
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 40)

                    if case .failed(let message) = service.state {
                        serviceFailure(message)
                            .padding(.bottom, 24)
                    }

                    SubscribedChannelsList(subscriptions: subscriptions,
                                           available: service.state == .ready) { channel in
                        openSubscription(channel)
                    }
                    .padding(.bottom, 28)

                    HistoryList(history: browser.history, available: service.state == .ready) { entry in
                        submit(entry.url.absoluteString)
                    }
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var homeSubtitle: String {
        switch service.state {
        case .idle, .starting:
            L10n.t("正在准备本地服务…")
        case .failed:
            L10n.t("本地服务暂时无法启动")
        case .ready:
            L10n.t("一个完全属于这台 Mac 的私密有序资料库。")
        }
    }

    private func serviceFailure(_ message: String) -> some View {
        HStack {
            Text(L10n.t(message)).lineLimit(1).help(L10n.t(message))
            Button(L10n.t("重试")) { service.restart() }
            Button(L10n.t("日志")) { service.revealDataDirectory() }
        }
        .font(.caption)
        .foregroundStyle(KumoTheme.subtle)
    }

    private func submit(_ value: String) {
        openPage(value)
    }

    private func openPage(_ value: String) {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let instanceURL = LocalServiceManager.invidiousURL
        guard let url = URLRouting.destination(for: input, instanceURL: instanceURL) else { return }
        if URLRouting.youtubeDestination(for: input, instanceURL: instanceURL) != nil {
            submittedYouTubeLinks[url] = input
        } else {
            submittedYouTubeLinks.removeValue(forKey: url)
        }
        visitAndShow(.page(url))
    }

    private func goHome() {
        visitAndShow(.home)
    }

    private func selectFolder(_ id: UUID) {
        guard favorites.folder(id) != nil else { return }
        visitAndShow(.folder(id))
    }

    private func openFavorite(_ video: FavoriteVideo) {
        guard let url = video.url else { return }
        visitAndShow(.page(url))
    }

    private func openSubscription(_ channel: ChannelSubscription) {
        visitAndShow(.page(channel.url))
    }

    private func toolbarGoBack() {
        while let destination = navigation.goBack() {
            if show(destination, replayDirection: .backward) { return }
        }
    }

    private func toolbarGoForward() {
        while let destination = navigation.goForward() {
            if show(destination, replayDirection: .forward) { return }
        }
    }

    private func navigateFromDetail(_ input: String) {
        openPage(input)
    }

    private func visitAndShow(_ destination: AppDestination) {
        navigation.visit(destination)
        _ = show(destination)
    }

    @discardableResult
    private func show(_ destination: AppDestination,
                      replayDirection: BrowserHistoryReplayDirection? = nil) -> Bool {
        searchFocused = false
        switch destination {
        case .home:
            query = toolbarQuery(for: destination)
            selectedFolderID = nil
            pendingPageLoad = nil
            browser.loadHome()
        case .folder(let id):
            guard favorites.folder(id) != nil else { return false }
            query = toolbarQuery(for: destination)
            selectedFolderID = id
            pendingPageLoad = nil
            browser.loadHome()
        case .page(let url):
            resignSearchFieldEditor()
            query = toolbarQuery(for: destination, submittedYouTubeLink: submittedYouTubeLinks[url])
            selectedFolderID = nil
            if service.state == .ready {
                pendingPageLoad = nil
                browser.loadPage(url, replayDirection: replayDirection)
            } else {
                pendingPageLoad = PendingPageLoad(url: url, replayDirection: replayDirection)
                service.start()
            }
        }
        return true
    }

    private func resignSearchFieldEditor() {
        searchFocused = false
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow,
                  let fieldEditor = window.firstResponder as? NSTextView,
                  fieldEditor.isFieldEditor else { return }
            window.makeFirstResponder(nil)
        }
    }

    private func synchronizeBrowserPage(_ change: BrowserPageChange) {
        guard change.sequence > 0, selectedFolderID == nil else { return }
        let destination = change.url.map(AppDestination.page) ?? .home
        switch change.direction {
        case .new:
            navigation.visit(destination)
        case .backward:
            if !navigation.moveBackward(to: destination) { navigation.visit(destination) }
        case .forward:
            if !navigation.moveForward(to: destination) { navigation.visit(destination) }
        case .replace(let sourceURL):
            if !navigation.replaceCurrent(from: .page(sourceURL), with: destination) {
                navigation.visit(destination)
            }
        }
    }
}

private struct ContentErrorAlerts: ViewModifier {
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var subscriptions: ChannelSubscriptionStore

    func body(content: Content) -> some View {
        content
            .alert(L10n.t("本地收藏夹"), isPresented: Binding(
                get: { favorites.errorMessage != nil },
                set: { if !$0 { favorites.errorMessage = nil } }
            )) {
                Button(L10n.t("好")) { favorites.errorMessage = nil }
            } message: {
                Text(L10n.t(favorites.errorMessage ?? ""))
            }
            .alert(L10n.t("本地订阅"), isPresented: Binding(
                get: { subscriptions.errorMessage != nil },
                set: { if !$0 { subscriptions.errorMessage = nil } }
            )) {
                Button(L10n.t("好")) { subscriptions.errorMessage = nil }
            } message: {
                Text(L10n.t(subscriptions.errorMessage ?? ""))
            }
    }
}

enum ToolbarSearchFieldLocator {
    static var placeholder: String { L10n.t("搜索或粘贴 YouTube 链接") }

    @MainActor
    static func focus(in window: NSWindow?) -> Bool {
        guard let window,
              let field = find(in: window.contentView?.superview) else { return false }
        field.selectText(nil)
        return true
    }

    @MainActor
    static func find(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.placeholderString == placeholder {
            return field
        }
        for subview in view.subviews {
            if let field = find(in: subview) { return field }
        }
        return nil
    }

    @MainActor
    static func shouldResignSearch(forClickAt locationInWindow: NSPoint,
                                   in window: NSWindow) -> Bool {
        guard let field = find(in: window.contentView?.superview),
              let editor = field.currentEditor(),
              editor === window.firstResponder else { return false }
        return !field.bounds.contains(field.convert(locationInWindow, from: nil))
    }
}

enum AppKeyboardShortcutAction: Equatable {
    case toggleSidebar
    case focusSearch
    case home
    case keyboardShortcuts
    case favoriteFolder(index: Int)
    case lastFavoriteFolder
    case back
    case forward
    case newFavoriteFolder
    case settings
    case saveVideo
    case theaterMode
    case cacheVideo
    case muteVideo
    case captions
}

enum AppKeyboardShortcut {
    static func action(for event: NSEvent, firstResponder: NSResponder?,
                       hasVideoDetail: Bool) -> AppKeyboardShortcutAction? {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command {
            if let key, let number = Int(key) {
                switch number {
                case 1: return .home
                case 2...8: return .favoriteFolder(index: number - 2)
                case 9: return .lastFavoriteFolder
                default: break
                }
            }
            switch key {
            case "k", "f": return .focusSearch
            case "n": return .newFavoriteFolder
            case ",": return .settings
            default: return nil
            }
        }

        if KeyboardShortcutsShortcut.matches(event, firstResponder: firstResponder) {
            return .keyboardShortcuts
        }

        guard modifiers.isEmpty,
              !(firstResponder is NSTextView || firstResponder is NSTextField) else { return nil }
        if event.keyCode == 123 { return .back }
        if event.keyCode == 124 { return .forward }
        if hasVideoDetail {
            switch key {
            case "b", "s": return .saveVideo
            case "f": return .theaterMode
            case "d": return .cacheVideo
            case "m": return .muteVideo
            case "c": return .captions
            default: break
            }
        }
        switch key {
        case "/": return .toggleSidebar
        case "h": return .home
        default: return nil
        }
    }
}

private struct AppKeyboardShortcutMonitor: NSViewRepresentable {
    let hasVideoDetail: Bool
    let modifierFlagsChanged: (NSEvent.ModifierFlags) -> Void
    let outsideSearchClicked: () -> Void
    let action: (AppKeyboardShortcutAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(hasVideoDetail: hasVideoDetail,
                    modifierFlagsChanged: modifierFlagsChanged,
                    outsideSearchClicked: outsideSearchClicked,
                    action: action)
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.window = window
        }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.hasVideoDetail = hasVideoDetail
        context.coordinator.modifierFlagsChanged = modifierFlagsChanged
        context.coordinator.outsideSearchClicked = outsideSearchClicked
        context.coordinator.action = action
        context.coordinator.window = nsView.window
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var hasVideoDetail: Bool
        var modifierFlagsChanged: (NSEvent.ModifierFlags) -> Void
        var outsideSearchClicked: () -> Void
        var action: (AppKeyboardShortcutAction) -> Void
        private var monitor: Any?

        init(hasVideoDetail: Bool,
             modifierFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
             outsideSearchClicked: @escaping () -> Void,
             action: @escaping (AppKeyboardShortcutAction) -> Void) {
            self.hasVideoDetail = hasVideoDetail
            self.modifierFlagsChanged = modifierFlagsChanged
            self.outsideSearchClicked = outsideSearchClicked
            self.action = action
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                self.modifierFlagsChanged(event.modifierFlags)
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    guard let window = self.window,
                          window.isKeyWindow,
                          window.attachedSheet == nil,
                          event.window === window,
                          ToolbarSearchFieldLocator.shouldResignSearch(
                            forClickAt: event.locationInWindow, in: window) else {
                        return event
                    }
                    self.outsideSearchClicked()
                    return event
                }
                guard event.type == .keyDown,
                      let window = self.window,
                      window.isKeyWindow,
                      window.attachedSheet == nil,
                      event.window == nil || event.window === window,
                      let shortcut = AppKeyboardShortcut.action(
                        for: event, firstResponder: window.firstResponder,
                        hasVideoDetail: self.hasVideoDetail) else {
                    return event
                }
                self.action(shortcut)
                return nil
            }
        }

        func invalidate() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    final class WindowTrackingView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}

private struct ToolbarIconButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let enabled: Bool
    let tooltipController: ToolbarTooltipController
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Button(action: action) {
                KumoIcon(icon, size: 16)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(KumoTheme.text)
                    .background(enabled && hovered ? KumoTheme.tint : .clear,
                                in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
            }
            .buttonStyle(ToolbarIconButtonStyle(reduceMotion: reduceMotion))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.42)
            .accessibilityLabel(label)
        }
        .frame(width: 36, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
        .background {
            ToolbarHoverRegion(label: label, shortcut: shortcut, controller: tooltipController) { value in
                hovered = value
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
    }
}

private struct ToolbarIconTooltip: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Text(shortcut)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .frame(width: 16, height: 16)
                .background(KumoTheme.bodyOnDark.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(KumoTheme.bodyOnDark.opacity(0.32), lineWidth: 1)
                }
        }
        .foregroundStyle(KumoTheme.bodyOnDark)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(KumoTheme.ink.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class ToolbarTooltipController: ObservableObject {
    private weak var sourceView: NSView?
    private var panel: NSPanel?

    func show(_ label: String, shortcut: String, relativeTo source: NSView) {
        guard let parent = source.window else { return }
        let panel = panel ?? makePanel(label: label, shortcut: shortcut)
        self.panel = panel
        sourceView = source

        guard let hostingView = panel.contentView as? NSHostingView<ToolbarIconTooltip> else { return }
        hostingView.rootView = ToolbarIconTooltip(label: label, shortcut: shortcut)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        panel.setContentSize(size)

        let anchor = parent.convertToScreen(source.convert(source.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let y = max(visible.minY + 6, anchor.minY - size.height - 6)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide(relativeTo source: NSView? = nil) {
        if let source, sourceView !== source { return }
        sourceView = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func makePanel(label: String, shortcut: String) -> NSPanel {
        let hostingView = NSHostingView(rootView: ToolbarIconTooltip(label: label, shortcut: shortcut))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = hostingView
        return panel
    }
}

private struct ToolbarHoverRegion: NSViewRepresentable {
    let label: String
    let shortcut: String
    let controller: ToolbarTooltipController
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: HoverTrackingView) {
        view.label = label
        view.shortcut = shortcut
        view.controller = controller
        view.hoverChanged = hoverChanged
    }

    final class HoverTrackingView: NSView {
        var label = ""
        var shortcut = ""
        weak var controller: ToolbarTooltipController?
        var hoverChanged: (Bool) -> Void = { _ in }
        private var trackingAreaReference: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
            let trackingArea = NSTrackingArea(rect: .zero,
                                              options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                              owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
            trackingAreaReference = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            hoverChanged(true)
            controller?.show(label, shortcut: shortcut, relativeTo: self)
        }

        override func mouseExited(with event: NSEvent) {
            hoverChanged(false)
            controller?.hide(relativeTo: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { controller?.hide(relativeTo: self) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

func toolbarQuery(for destination: AppDestination, submittedYouTubeLink: String? = nil) -> String {
    guard case .page(let url) = destination else { return "" }
    if let submittedYouTubeLink { return submittedYouTubeLink }
    return SearchPageRoute(url)?.query ?? ""
}

private struct HistoryList: View {
    @ObservedObject var history: WatchHistory
    let available: Bool
    let open: (WatchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.t("最近观看")).font(.system(size: 15, weight: .semibold))
                Spacer()
                if !history.entries.isEmpty {
                    Text(L10n.t("\(history.entries.count) 个视频")).font(.caption).foregroundStyle(KumoTheme.subtle)
                }
            }
            if history.entries.isEmpty {
                HStack(spacing: 12) {
                    KumoIcon("clock-counter-clockwise").font(.title3)
                    Text(L10n.t("播放过的视频会出现在这里")).font(.callout)
                }
                .foregroundStyle(KumoTheme.subtle)
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                LazyVGrid(columns: nativeVideoCardColumns, alignment: .leading, spacing: 22) {
                    ForEach(history.entries) { entry in
                        NativeVideoCard(videoID: entry.id, title: entry.title,
                                        author: nil, authorID: nil, metadata: nil,
                                        lengthSeconds: nil,
                                        thumbnailAvailable: available,
                                        relativeDate: entry.watchedAt,
                                        openVideo: { open(entry) },
                                        openChannel: { _ in })
                        .accessibilityLabel(L10n.t("播放 \(entry.title)"))
                    }
                }
            }
        }
    }
}

struct YouTubeLogo: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: proxy.size.height * 0.23)
                    .fill(Color(red: 1, green: 0, blue: 0))
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.40, y: proxy.size.height * 0.28))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.40, y: proxy.size.height * 0.72))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.68, y: proxy.size.height * 0.50))
                    path.closeSubpath()
                }
                .fill(KumoTheme.bodyOnDark)
            }
        }
        .accessibilityLabel("YouTube")
    }
}
