import SwiftUI
import UserNotifications

@main
struct YootubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.zhHans

    var body: some Scene {
        Window("", id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
                .background(StandardWindowChrome())
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(L10n.t("聚焦搜索")) {
                    NotificationCenter.default.post(name: .focusLocation, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button(L10n.t("聚焦搜索（⌘K）")) {
                    NotificationCenter.default.post(name: .focusLocation, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(L10n.t("聚焦搜索（⌘F）")) {
                    NotificationCenter.default.post(name: .focusLocation, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(L10n.t("新建收藏夹")) {
                    NotificationCenter.default.post(name: .newFavoriteFolder, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(L10n.t("返回主页")) {
                    NotificationCenter.default.post(name: .goHome, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button(L10n.t("展开/收起侧栏")) {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
        }
    }
}

// Fixed product requirement. Feature work must leave the native window chrome intact.
struct StandardWindowChrome: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.dark = colorScheme == .dark
        return view
    }
    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.dark = colorScheme == .dark
        nsView.applyStyle()
    }

    final class ChromeView: NSView {
        var dark = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyStyle()
        }

        func applyStyle() {
            guard let window else { return }
            StandardWindowChrome.apply(to: window)
            window.backgroundColor = KumoTheme.windowColor(dark: dark)
            DispatchQueue.main.async {
                StandardWindowChrome.apply(to: window)
                StandardWindowChrome.applyToolbarMaterial(to: window, dark: self.dark)
            }
        }
    }

    static func apply(to window: NSWindow) {
        // Let AppKit own fullscreen transitions; page updates must not alter them.
        guard !window.styleMask.contains(.fullScreen) else { return }
        let required: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar
        ]
        let style = window.styleMask.union(required).subtracting(.fullSizeContentView)
        if window.styleMask != style { window.styleMask = style }
        if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = false }
        if window.titleVisibility != .visible { window.titleVisibility = .visible }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if window.toolbar?.showsBaselineSeparator == true {
            window.toolbar?.showsBaselineSeparator = false
        }
        if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
    }

    static func applyToolbarMaterial(to window: NSWindow, dark: Bool) {
        guard !window.styleMask.contains(.fullScreen),
              let contentView = window.contentView,
              let frameView = contentView.superview else { return }
        window.titlebarSeparatorStyle = .none
        window.toolbar?.showsBaselineSeparator = false
        let titlebarOrigin = contentView.frame.maxY
        for view in frameView.subviews where view !== contentView && view.frame.maxY > titlebarOrigin {
            updateTitlebarEffects(in: view, titlebarWidth: frameView.bounds.width, dark: dark)
        }
    }

    private static func updateTitlebarEffects(in view: NSView, titlebarWidth: CGFloat, dark: Bool) {
        if view.frame.height > 0, view.frame.height <= 1,
           view.frame.width >= titlebarWidth - 1 {
            view.isHidden = true
        }
        if let effect = view as? NSVisualEffectView,
           effect.material == .contentBackground {
            effect.material = .sidebar
            effect.alphaValue = dark ? 0 : 0.50
        }
        view.subviews.forEach {
            updateTitlebarEffects(in: $0, titlebarWidth: titlebarWidth, dark: dark)
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("Yootube.appLanguageDidChange")
    static let focusLocation = Notification.Name("Yootube.focusLocation")
    static let goHome = Notification.Name("Yootube.goHome")
    static let toggleSidebar = Notification.Name("Yootube.toggleSidebar")
    static let newFavoriteFolder = Notification.Name("Yootube.newFavoriteFolder")
    static let showVideoFavoritePicker = Notification.Name("Yootube.showVideoFavoritePicker")
    static let showVideoCachePicker = Notification.Name("Yootube.showVideoCachePicker")
    static let openChannelUpdateVideo = Notification.Name("Yootube.openChannelUpdateVideo")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var terminationSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppUpdater.shared
        UNUserNotificationCenter.current().delegate = self
        terminationSources = [SIGTERM, SIGINT].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NSApplication.shared.terminate(nil)
            }
            source.resume()
            return source
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalServiceManager.shared.stop()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let videoID = response.notification.request.content.userInfo["videoID"] as? String,
              VideoRoute.watchURL(id: videoID) != nil else {
            completionHandler()
            return
        }
        UserDefaults.standard.set(videoID, forKey: "pendingChannelNotificationVideoID")
        completionHandler()
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .openChannelUpdateVideo, object: nil)
        }
    }
}
