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
            settingsDetail
        }
        .frame(width: 760, height: 560)
        .background(KumoTheme.canvas)
        .foregroundStyle(KumoTheme.text)
        .buttonStyle(SettingsQuietButtonStyle())
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsCategory.allCases) { item in
                SettingsCategoryButton(item: item, selected: category == item) {
                    category = item
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                KumoIcon("lock", size: 13)
                Text(L10n.t("数据保存在本地"))
                    .font(.system(size: 11))
            }
            .foregroundStyle(KumoTheme.subtle)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: 196)
        .background(KumoTheme.sidebar)
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(category.title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.2)
                switch category {
                case .general: generalSettings
                case .data: dataSettings
                case .service: serviceSettings
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KumoTheme.canvas)
    }

    private var generalSettings: some View {
        VStack(spacing: 0) {
            SettingsRow(title: L10n.t("App 语言"),
                        detail: L10n.t("更改会立即应用到所有窗口。")) {
                Menu {
                    ForEach(AppLanguage.allCases) { option in
                        Button {
                            language = option
                        } label: {
                            if language == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(language.title)
                        Spacer(minLength: 8)
                        KumoIcon("caret-down", size: 12)
                    }
                    .frame(width: 110)
                }
                .menuIndicator(.hidden)
                .buttonStyle(SettingsQuietButtonStyle())
            }
            SettingsRow(title: L10n.t("外观")) {
                SettingsSegmentedControl(options: AppAppearance.allCases,
                                          title: { $0.title },
                                          selection: $appearance)
            }
            SettingsRow(title: L10n.t("键盘快捷键"),
                        detail: L10n.t("查看导航、收藏夹和视频播放快捷键，也可以随时按 ? 打开。")) {
                Button(L10n.t("查看快捷键")) { showsKeyboardShortcuts = true }
            }
        }
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsGroup(title: L10n.t("本地数据"),
                          footer: L10n.t("视频缓存不会包含在备份文件中。")) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("数据保存在本地"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L10n.t("频道订阅、收藏夹、播放列表和最近观看只保存在此 Mac。"))
                        .font(.system(size: 12))
                        .foregroundStyle(KumoTheme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)

                HStack(spacing: 8) {
                    Button { chooseImportFile() } label: {
                        KumoLabel(L10n.t("导入备份"), icon: "download-simple")
                    }
                    Button { exportBackup() } label: {
                        KumoLabel(L10n.t("导出备份"), icon: "floppy-disk")
                    }
                    Spacer(minLength: 8)
                    Button(L10n.t("打开数据目录")) { service.revealDataDirectory() }
                }
                .padding(.bottom, 4)
            }

            SettingsGroup(title: L10n.t("缓存")) {
                SettingsRow(title: L10n.t("图片缓存"),
                            detail: L10n.t("封面、头像和横幅 · 已使用 \(imageCacheSizeText) / 300 MB")) {
                    Button(L10n.t("清除")) { clearImageCache() }
                        .disabled(imageCacheBytes == 0)
                }
                SettingsRow(title: L10n.t("视频缓存"),
                            detail: L10n.t("\(videoCache.entries.count) 个视频 · \(videoCacheSizeText)")) {
                    Button(L10n.t("清除")) { showsClearVideoCacheConfirmation = true }
                        .disabled(videoCache.entries.isEmpty || videoCache.isCaching)
                }
            }
        }
    }

    private var serviceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: L10n.t("本地 Invidious"),
                          footer: L10n.t("Invidious、PostgreSQL 和视频代理随 Yootube 启动，只监听此 Mac 的回环地址。出站连接使用 macOS 系统代理。")) {
                SettingsRow(title: L10n.t("运行状态"), detail: statusDetail) {
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(statusText).font(.system(size: 13, weight: .medium))
                    }
                }
                SettingsRow(title: L10n.t("服务地址")) {
                    Text("127.0.0.1:38473")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KumoTheme.subtle)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Button(L10n.t("重启本地服务")) { service.restart() }
                    .buttonStyle(SettingsPrimaryButtonStyle())
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
                KumoIcon(item.icon, size: 18)
                    .frame(width: 18, height: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 12)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KumoTheme.subtle)
            VStack(alignment: .leading, spacing: 0) { content() }
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(KumoTheme.subtle)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(KumoTheme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 13)
        .frame(minHeight: 48)
    }
}

private struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Option?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selection)
    }

    private func segment(_ option: Option) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            Text(title(option))
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? KumoTheme.text : KumoTheme.subtle)
                .padding(.horizontal, 10)
                .frame(minWidth: 76, minHeight: 26)
                .background(segmentFill(selected: selected, option: option),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? L10n.t("已选择") : L10n.t("未选择"))
        .onHover { hovering in
            hovered = hovering ? option : (hovered == option ? nil : hovered)
        }
    }

    private var track: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    private func segmentFill(selected: Bool, option: Option) -> Color {
        if selected {
            return colorScheme == .dark ? Color.white.opacity(0.14) : KumoTheme.canvas
        }
        if hovered == option {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
        }
        return .clear
    }
}

private struct SettingsQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsFillButtonBody(configuration: configuration, prominent: false)
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsFillButtonBody(configuration: configuration, prominent: true)
    }
}

private struct SettingsFillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .foregroundStyle(prominent ? KumoTheme.bodyOnDark : KumoTheme.text)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 }
    }

    private var fill: Color {
        let hot = enabled && (hovered || configuration.isPressed)
        if prominent {
            return KumoTheme.brand.opacity(hot ? 0.84 : 1)
        }
        if colorScheme == .dark {
            return Color.white.opacity(hot ? 0.12 : 0.06)
        }
        return Color.black.opacity(hot ? 0.08 : 0.045)
    }
}
