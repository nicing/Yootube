import AppKit
import SwiftUI
import UserNotifications

struct ChannelUpdateNotification: Codable, Identifiable, Equatable {
    let id: String
    let videoID: String
    let videoTitle: String
    let channelID: String
    let channelName: String
    let publishedAt: Date?
    let publishedText: String?
    let detectedAt: Date
    var isRead: Bool

    var videoURL: URL? { VideoRoute.watchURL(id: videoID) }

    func publicationSortDate(relativeTo referenceDate: Date) -> Date {
        publishedAt ?? estimatedPublicationAge.map { referenceDate.addingTimeInterval(-$0) } ?? detectedAt
    }

    private var estimatedPublicationAge: TimeInterval? {
        guard let text = publishedText?.lowercased(),
              let digits = text.split(whereSeparator: { !$0.isNumber }).first,
              let value = TimeInterval(digits) else { return nil }
        let unit: TimeInterval
        if text.contains("second") || text.contains("秒") { unit = 1 }
        else if text.contains("minute") || text.contains("分钟") { unit = 60 }
        else if text.contains("hour") || text.contains("小时") { unit = 3_600 }
        else if text.contains("day") || text.contains("天") { unit = 86_400 }
        else if text.contains("week") || text.contains("周") { unit = 604_800 }
        else if text.contains("month") || text.contains("月") { unit = 2_592_000 }
        else if text.contains("year") || text.contains("年") { unit = 31_536_000 }
        else { return nil }
        return value * unit
    }
}

@MainActor
final class ChannelNotificationStore: ObservableObject {
    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Yootube/channel-notifications.json")

    @Published private(set) var notifications: [ChannelUpdateNotification] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var systemAuthorization = UNAuthorizationStatus.notDetermined
    @Published var errorMessage: String?

    var unreadCount: Int { notifications.lazy.filter { !$0.isRead }.count }

    let fileURL: URL
    private let fetchChannel: (String) async throws -> NativeChannel
    private let injectedNotificationCenter: UNUserNotificationCenter?
    private var knownVideoIDsByChannel: [String: [String]] = [:]

    init(
        fileURL: URL = ChannelNotificationStore.defaultFileURL,
        notificationCenter: UNUserNotificationCenter? = nil,
        fetchChannel: @escaping (String) async throws -> NativeChannel = { channelID in
            try await VideoAPI.fetch(NativeChannel.self, path: "api/v1/channels/\(channelID)")
        }
    ) {
        self.fileURL = fileURL
        injectedNotificationCenter = notificationCenter
        self.fetchChannel = fetchChannel
        reload()
    }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(ChannelNotificationsDocument.self, from: data)
            try Self.validate(document)
            let sortReference = Date()
            notifications = document.notifications.sorted {
                $0.publicationSortDate(relativeTo: sortReference) >
                    $1.publicationSortDate(relativeTo: sortReference)
            }
            knownVideoIDsByChannel = document.knownVideoIDsByChannel
            lastCheckedAt = document.lastCheckedAt
            isLoaded = true
            errorMessage = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            _ = save(notifications: [], knownVideoIDsByChannel: [:], lastCheckedAt: nil)
        } catch {
            isLoaded = false
            errorMessage = L10n.t("无法读取频道通知，原文件已保留。")
        }
    }

    func checkForUpdates(
        in subscriptions: [ChannelSubscription],
        minimumInterval: TimeInterval = 15 * 60,
        deliverSystemNotifications: Bool = true
    ) async {
        guard isLoaded, !isChecking else { return }
        let subscribedIDs = Set(subscriptions.map(\.id))
        let needsBaseline = subscribedIDs.contains { knownVideoIDsByChannel[$0] == nil }
        let subscriptionSetChanged = Set(knownVideoIDsByChannel.keys) != subscribedIDs
        if !needsBaseline, !subscriptionSetChanged, let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < minimumInterval { return }

        isChecking = true
        defer { isChecking = false }

        var updatedKnown = knownVideoIDsByChannel.filter { subscribedIDs.contains($0.key) }
        var newNotifications: [ChannelUpdateNotification] = []
        var completedAt: Date?

        for subscription in subscriptions {
            do {
                let channel = try await fetchChannel(subscription.id)
                let latestVideos = Array(channel.latestVideos.prefix(30))
                if let knownIDs = updatedKnown[subscription.id] {
                    let known = Set(knownIDs)
                    let alreadyRecorded = Set(notifications.map(\.id))
                        .union(newNotifications.map(\.id))
                    let detectedAt = Date()
                    newNotifications.append(contentsOf: latestVideos.compactMap { video in
                        let id = "\(subscription.id):\(video.videoId)"
                        guard !known.contains(video.videoId), !alreadyRecorded.contains(id) else { return nil }
                        return ChannelUpdateNotification(
                            id: id,
                            videoID: video.videoId,
                            videoTitle: video.title,
                            channelID: subscription.id,
                            channelName: channel.author,
                            publishedAt: video.published.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                            publishedText: video.publishedText,
                            detectedAt: detectedAt,
                            isRead: false
                        )
                    })
                }
                updatedKnown[subscription.id] = latestVideos.map(\.videoId)
                completedAt = Date()
            } catch {
                continue
            }
        }

        if subscriptions.isEmpty { completedAt = Date() }
        guard let completedAt else { return }
        let sortReference = Date()
        let updatedNotifications = Array((newNotifications + notifications)
            .sorted {
                $0.publicationSortDate(relativeTo: sortReference) >
                    $1.publicationSortDate(relativeTo: sortReference)
            }
            .prefix(200))
        guard save(notifications: updatedNotifications,
                   knownVideoIDsByChannel: updatedKnown,
                   lastCheckedAt: completedAt) else { return }

        if deliverSystemNotifications, !newNotifications.isEmpty {
            await deliver(newNotifications)
        }
    }

    func markRead(_ id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }),
              !notifications[index].isRead else { return }
        var updated = notifications
        updated[index].isRead = true
        _ = save(notifications: updated,
                 knownVideoIDsByChannel: knownVideoIDsByChannel,
                 lastCheckedAt: lastCheckedAt)
    }

    func markVideoRead(_ videoID: String) {
        guard let notification = notifications.first(where: { $0.videoID == videoID }) else { return }
        markRead(notification.id)
    }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        let updated = notifications.map { item in
            var copy = item
            copy.isRead = true
            return copy
        }
        _ = save(notifications: updated,
                 knownVideoIDsByChannel: knownVideoIDsByChannel,
                 lastCheckedAt: lastCheckedAt)
    }

    func refreshSystemAuthorization() async {
        systemAuthorization = await notificationCenter.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestSystemAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            await refreshSystemAuthorization()
            return granted
        } catch {
            await refreshSystemAuthorization()
            return false
        }
    }

    private func deliver(_ updates: [ChannelUpdateNotification]) async {
        await refreshSystemAuthorization()
        if systemAuthorization == .notDetermined {
            let granted = await requestSystemAuthorization()
            guard granted else { return }
        }
        guard [.authorized, .provisional].contains(systemAuthorization) else { return }

        for update in updates {
            let content = UNMutableNotificationContent()
            content.title = update.channelName
            content.body = update.videoTitle
            content.sound = .default
            content.userInfo = ["videoID": update.videoID]
            let request = UNNotificationRequest(identifier: "channel-update-\(update.id)",
                                                content: content,
                                                trigger: nil)
            try? await notificationCenter.add(request)
        }
    }

    private var notificationCenter: UNUserNotificationCenter {
        injectedNotificationCenter ?? .current()
    }

    private func save(notifications: [ChannelUpdateNotification],
                      knownVideoIDsByChannel: [String: [String]],
                      lastCheckedAt: Date?) -> Bool {
        do {
            let document = ChannelNotificationsDocument(
                notifications: notifications,
                knownVideoIDsByChannel: knownVideoIDsByChannel,
                lastCheckedAt: lastCheckedAt
            )
            try Self.validate(document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            self.notifications = notifications
            self.knownVideoIDsByChannel = knownVideoIDsByChannel
            self.lastCheckedAt = lastCheckedAt
            isLoaded = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.t("频道通知保存失败，此次更改未生效。")
            return false
        }
    }

    nonisolated private static func validate(_ document: ChannelNotificationsDocument) throws {
        let notifications = document.notifications
        guard notifications.count <= 200,
              Set(notifications.map(\.id)).count == notifications.count,
              notifications.allSatisfy({ notification in
                  !notification.id.isEmpty && notification.id.count <= 300 &&
                  !notification.channelID.isEmpty && notification.channelID.count <= 128 &&
                  !notification.channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  notification.channelName.count <= 200 &&
                  !notification.videoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  notification.videoTitle.count <= 500 &&
                  VideoRoute.watchURL(id: notification.videoID) != nil
              }),
              document.knownVideoIDsByChannel.count <= 10_000,
              document.knownVideoIDsByChannel.allSatisfy({ channelID, videoIDs in
                  !channelID.isEmpty && channelID.count <= 128 && videoIDs.count <= 30 &&
                  Set(videoIDs).count == videoIDs.count &&
                  videoIDs.allSatisfy { VideoRoute.watchURL(id: $0) != nil }
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

private struct ChannelNotificationsDocument: Codable {
    let notifications: [ChannelUpdateNotification]
    let knownVideoIDsByChannel: [String: [String]]
    let lastCheckedAt: Date?
}

struct ChannelNotificationsPanel: View {
    @ObservedObject var store: ChannelNotificationStore
    let close: () -> Void
    let open: (ChannelUpdateNotification) -> Void
    @State private var markAllHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("频道更新"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !store.notifications.isEmpty {
                    Button { store.markAllRead() } label: {
                        Text(L10n.t("全部已读"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(markAllHovered && store.unreadCount > 0 ? KumoTheme.text : KumoTheme.subtle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(markAllHovered && store.unreadCount > 0 ? KumoTheme.tint : .clear,
                                        in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                    }
                        .buttonStyle(.plain)
                        .disabled(store.unreadCount == 0)
                        .onHover { markAllHovered = $0 }
                }
            }
            .padding(16)

            if !store.isLoaded {
                notificationEmptyState(icon: "bell", text: L10n.t("频道通知暂时无法读取"))
            } else if store.notifications.isEmpty {
                notificationEmptyState(icon: "bell", text: L10n.t("订阅频道有新视频时会显示在这里"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.notifications) { notification in
                            ChannelNotificationRow(notification: notification) {
                                store.markRead(notification.id)
                                open(notification)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: min(CGFloat(store.notifications.count) * 72 + 16, 420))
            }

            if store.systemAuthorization == .notDetermined {
                Button {
                    Task { _ = await store.requestSystemAuthorization() }
                } label: {
                    KumoLabel(L10n.t("开启系统通知"), icon: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(KumoButtonStyle(variant: .ghost))
                .padding(8)
            }
        }
        .frame(width: 360)
        .background(KumoTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(KumoTheme.line, lineWidth: 1)
        }
        .shadow(color: KumoTheme.surfaceBlack.opacity(0.12), radius: 18, y: 8)
        .background(WindowOutsideClickMonitor(action: close))
        .task { await store.refreshSystemAuthorization() }
    }

    private func notificationEmptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            KumoIcon(icon, size: 22)
            Text(text).font(.callout)
        }
        .foregroundStyle(KumoTheme.subtle)
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.horizontal, 24)
    }
}

private struct WindowOutsideClickMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.action = action
        context.coordinator.install(for: nsView)
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        private weak var monitoredWindow: NSWindow?
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func install(for view: TrackingView) {
            guard let window = view.window else { return }
            if monitoredWindow !== window { invalidate() }
            guard monitor == nil else { return }
            monitoredWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseUp, .rightMouseUp]
            ) { [weak self, weak view] event in
                guard let self, let view, event.window === self.monitoredWindow else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard !view.bounds.contains(point) else { return event }
                DispatchQueue.main.async { [weak self] in self?.action() }
                return event
            }
        }

        func invalidate() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            monitoredWindow = nil
        }
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.install(for: self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct ChannelNotificationRow: View {
    let notification: ChannelUpdateNotification
    let action: () -> Void
    @ObservedObject private var service = LocalServiceManager.shared
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                NativeRemoteImage(url: VideoAPI.thumbnailURL(notification.videoID), icon: "play")
                    .id(service.state == .ready)
                    .frame(width: 88, height: 50)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(KumoTheme.line, lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.videoTitle)
                        .font(.system(size: 13, weight: notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(notification.channelName)
                        if let publishedText = notification.publishedText, !publishedText.isEmpty {
                            Text("·")
                            Text(publishedText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(KumoTheme.subtle)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
            .background(hovered ? KumoTheme.tint : .clear,
                        in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(L10n.t("播放 \(notification.videoTitle)"))
    }
}
