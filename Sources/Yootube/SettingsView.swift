import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case data
    case service

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L10n.t("通用")
        case .data: L10n.t("数据与缓存")
        case .service: L10n.t("本地服务")
        }
    }
    var icon: String {
        switch self {
        case .general: "gear-six"
        case .data: "hard-drive"
        case .service: "desktop"
        }
    }
}

struct SettingsView: View {
    @StateObject private var service = LocalServiceManager.shared
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var subscriptions = ChannelSubscriptionStore()
    @StateObject private var history = WatchHistory()
    @StateObject private var videoCache = VideoCacheStore.shared
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.zhHans
    @State private var category = SettingsCategory.general
    @State private var pendingImport: LocalDataArchive?
    @State private var showsImportChoice = false
    @State private var notice: TransferNotice?
    @State private var imageCacheBytes = 0
    @State private var showsClearVideoCacheConfirmation = false
    @State private var showsKeyboardShortcuts = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(width: 760, height: 560)
        .background(KumoTheme.canvas)
        .foregroundStyle(KumoTheme.text)
        .buttonStyle(KumoButtonStyle())
        .tint(KumoTheme.brand)
        .background {
            KeyboardShortcutsShortcutMonitor { showsKeyboardShortcuts = true }
                .frame(width: 0, height: 0)
        }
        .onAppear { refreshImageCacheSize() }
        .onChange(of: language) { _, _ in
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
        .sheet(isPresented: $showsKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .confirmationDialog(L10n.t("本机已有数据"), isPresented: $showsImportChoice,
                            titleVisibility: .visible) {
            Button(L10n.t("合并数据")) { performImport(.merge) }
            Button(L10n.t("覆盖本机数据"), role: .destructive) { performImport(.replace) }
            Button(L10n.t("取消"), role: .cancel) { pendingImport = nil }
        } message: {
            Text(L10n.t("合并会保留本机内容并去重；覆盖会用备份内容替换本机收藏夹、订阅和最近观看。导入前都会自动备份现有数据。"))
        }
        .confirmationDialog(L10n.t("清除全部视频缓存？"), isPresented: $showsClearVideoCacheConfirmation,
                            titleVisibility: .visible) {
            Button(L10n.t("清除全部视频缓存"), role: .destructive) { clearVideoCache() }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t("将删除 \(videoCache.entries.count) 个已缓存视频。收藏夹、订阅和观看记录不会受到影响。"))
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message),
                  dismissButton: .default(Text(L10n.t("好"))))
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("设置"))
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 4)

            VStack(spacing: 4) {
                ForEach(SettingsCategory.allCases) { item in
                    SettingsCategoryButton(item: item, selected: category == item) {
                        category = item
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                KumoIcon("lock", size: 14)
                Text(L10n.t("数据保存在本地"))
                    .font(.system(size: 11))
            }
            .foregroundStyle(KumoTheme.subtle)
            .padding(.horizontal, 12)
        }
        .padding(12)
        .frame(width: 190)
        .background(KumoTheme.sidebar)
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(category.title)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.3)
                switch category {
                case .general: generalSettings
                case .data: dataSettings
                case .service: serviceSettings
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KumoTheme.canvas)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.t("语言")) {
                SettingsRow(icon: "globe", title: L10n.t("App 语言"),
                            detail: L10n.t("更改会立即应用到所有窗口。")) {
                    Picker(L10n.t("语言"), selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
            }

            SettingsGroup(title: L10n.t("外观")) {
                HStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { mode in
                        Button { appearance = mode } label: {
                            KumoLabel(mode.title, icon: mode.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(KumoButtonStyle(variant: appearance == mode ? .primary : .secondary))
                        .accessibilityValue(appearance == mode ? L10n.t("已选择") : L10n.t("未选择"))
                    }
                }
                .padding(12)
            }

            SettingsGroup(title: L10n.t("键盘")) {
                SettingsRow(icon: "code", title: L10n.t("键盘快捷键"),
                            detail: L10n.t("查看导航、收藏夹和视频播放快捷键，也可以随时按 ? 打开。")) {
                    Button(L10n.t("查看快捷键")) { showsKeyboardShortcuts = true }
                }
            }
        }
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.t("本地数据"),
                          footer: L10n.t("视频缓存不会包含在备份文件中。")) {
                SettingsRow(icon: "lock", title: L10n.t("数据保存在本地"),
                            detail: L10n.t("频道订阅、收藏夹、播放列表和最近观看只保存在此 Mac。")) {
                    EmptyView()
                }
                SettingsDivider()
                HStack(spacing: 8) {
                    Button { chooseImportFile() } label: {
                        KumoLabel(L10n.t("导入备份"), icon: "download-simple")
                    }
                    Button { exportBackup() } label: {
                        KumoLabel(L10n.t("导出备份"), icon: "floppy-disk")
                    }
                    Spacer()
                    Button(L10n.t("打开数据目录")) { service.revealDataDirectory() }
                }
                .padding(12)
            }

            SettingsGroup(title: L10n.t("缓存")) {
                SettingsRow(icon: "hard-drive", title: L10n.t("图片缓存"),
                            detail: L10n.t("封面、头像和横幅 · 已使用 \(imageCacheSizeText) / 300 MB")) {
                    Button(L10n.t("清除")) { clearImageCache() }
                        .disabled(imageCacheBytes == 0)
                }
                SettingsDivider()
                SettingsRow(icon: "video-camera", title: L10n.t("视频缓存"),
                            detail: L10n.t("\(videoCache.entries.count) 个视频 · \(videoCacheSizeText)")) {
                    Button(L10n.t("清除")) { showsClearVideoCacheConfirmation = true }
                        .disabled(videoCache.entries.isEmpty || videoCache.isCaching)
                }
            }
        }
    }

    private var serviceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.t("本地 Invidious"),
                          footer: L10n.t("Invidious、PostgreSQL 和视频代理随 Yootube 启动，只监听此 Mac 的回环地址。出站连接使用 macOS 系统代理。")) {
                SettingsRow(icon: "check-circle", title: L10n.t("运行状态"), detail: statusDetail) {
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(statusText).font(.system(size: 12, weight: .medium))
                    }
                }
                SettingsDivider()
                SettingsRow(icon: "link-simple", title: L10n.t("服务地址"), detail: nil) {
                    Text("127.0.0.1:38473")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KumoTheme.subtle)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Button(L10n.t("重启本地服务")) { service.restart() }
                    .buttonStyle(KumoButtonStyle(variant: .primary))
                Button(L10n.t("打开日志目录")) { service.revealLogsDirectory() }
            }
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .ready: .green
        case .failed: KumoTheme.brand
        case .idle, .starting: KumoTheme.subtle
        }
    }

    private var statusDetail: String? {
        switch service.state {
        case .starting(let message), .failed(let message): L10n.t(message)
        case .idle, .ready: nil
        }
    }

    private func refreshData() {
        favorites.reload()
        subscriptions.reload()
        history.reload()
    }

    private func refreshImageCacheSize() {
        Task { imageCacheBytes = await ImageCacheStore.shared.currentDiskUsageBytes }
    }

    private func clearImageCache() {
        Task {
            await ImageCacheStore.shared.removeAllCachedImages()
            imageCacheBytes = await ImageCacheStore.shared.currentDiskUsageBytes
        }
    }

    private var imageCacheSizeText: String { byteCountText(Int64(imageCacheBytes)) }
    private var videoCacheSizeText: String { byteCountText(videoCache.totalByteCount) }

    private func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    private func clearVideoCache() {
        do {
            try videoCache.removeAll()
            notice = TransferNotice(title: L10n.t("清理完成"), message: L10n.t("本地视频缓存已全部清除。"))
        } catch {
            notice = TransferNotice(title: L10n.t("无法清除视频缓存"), message: error.localizedDescription)
        }
    }

    private func exportBackup() {
        do {
            refreshData()
            let archive = try LocalDataTransfer.makeArchive(
                favorites: favorites, subscriptions: subscriptions, history: history)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Yootube-Backup-\(Self.filenameDate.string(from: Date())).json"
            panel.message = L10n.t("导出频道订阅、收藏夹与最近观看")
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    do {
                        try LocalDataTransfer.encode(archive).write(to: url, options: .atomic)
                        notice = TransferNotice(title: L10n.t("导出完成"),
                                                message: L10n.t("Yootube 本地数据已保存到你选择的位置。"))
                    } catch {
                        notice = TransferNotice(title: L10n.t("导出失败"), message: error.localizedDescription)
                    }
                }
            }
        } catch {
            notice = TransferNotice(title: L10n.t("无法导出"), message: error.localizedDescription)
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.t("选择 Yootube JSON 备份文件")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let archive = try LocalDataTransfer.decode(contentsOf: url)
                    refreshData()
                    pendingImport = archive
                    if LocalDataTransfer.hasUserData(
                        favorites: favorites, subscriptions: subscriptions, history: history) {
                        showsImportChoice = true
                    } else {
                        performImport(.replace)
                    }
                } catch {
                    pendingImport = nil
                    notice = TransferNotice(title: L10n.t("无法导入"), message: error.localizedDescription)
                }
            }
        }
    }

    private func performImport(_ mode: LocalDataImportMode) {
        guard let archive = pendingImport else { return }
        do {
            let backupDirectory = service.dataDirectory.appendingPathComponent("Backups", isDirectory: true)
            _ = try LocalDataTransfer.apply(
                archive, mode: mode, favorites: favorites,
                subscriptions: subscriptions, history: history,
                backupDirectory: backupDirectory)
            NotificationCenter.default.post(name: .localDataImported, object: nil)
            pendingImport = nil
            notice = TransferNotice(title: L10n.t("导入完成"),
                                    message: L10n.t("收藏夹、频道订阅和最近观看已恢复。导入前的数据已自动备份。"))
        } catch {
            pendingImport = nil
            notice = TransferNotice(title: L10n.t("导入失败"), message: error.localizedDescription)
        }
    }

    private static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct TransferNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var statusText: String {
        switch service.state {
        case .idle: L10n.t("未启动")
        case .starting: L10n.t("启动中")
        case .ready: L10n.t("运行中")
        case .failed: L10n.t("启动失败")
        }
    }
}

private struct SettingsCategoryButton: View {
    let item: SettingsCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                KumoIcon(item.icon, size: 17).frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected || hovered ? KumoTheme.tint : .clear,
                    in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KumoTheme.subtle)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(KumoTheme.base, in: RoundedRectangle(cornerRadius: KumoTheme.radiusPanel))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(KumoTheme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(icon: String, title: String, detail: String?, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            KumoIcon(icon, size: 17)
                .foregroundStyle(KumoTheme.subtle)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(KumoTheme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }
}

private struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 48) }
}
