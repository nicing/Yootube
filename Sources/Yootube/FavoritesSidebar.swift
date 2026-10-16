import SwiftUI
import UniformTypeIdentifiers

struct FavoritesSidebar: View {
    @ObservedObject var favorites: FavoritesStore
    let selectedFolderID: UUID?
    let isHome: Bool
    let showsShortcutHints: Bool
    let selectFolder: (UUID) -> Void
    let goHome: () -> Void
    @State private var showsEditor = false
    @State private var editingFolder: FavoriteFolder?
    @State private var deletingFolder: FavoriteFolder?
    @State private var hoveredFolderID: UUID?
    @State private var folderDropInsertion: FolderDropInsertion?
    @State private var videoDropTargetID: UUID?
    @State private var homeHovered = false

    private let folderRowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: goHome) {
                    HStack(spacing: 10) {
                        KumoIcon("house", size: 18)
                            .frame(width: 18, height: 18)
                        Text(L10n.t("首页"))
                            .font(.system(size: 13, weight: isHome ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if showsShortcutHints {
                            SidebarShortcutHintBadge(label: SidebarShortcutHints.homeLabel,
                                                     emphasized: isHome)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(isHome || homeHovered ? KumoTheme.tint : .clear,
                            in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                .onHover { homeHovered = $0 }
                .help(L10n.t("首页"))
                .accessibilityLabel(L10n.t("首页"))

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(favorites.folders.enumerated()), id: \.element.id) { index, folder in
                            if let insertion = folderDropInsertion,
                               insertion == FolderDropInsertion(targetFolderID: folder.id, placeAfter: false) {
                                folderInsertionPlaceholder(insertion)
                            }
                            folderRow(folder, at: index)
                            if let insertion = folderDropInsertion,
                               insertion == FolderDropInsertion(targetFolderID: folder.id, placeAfter: true) {
                                folderInsertionPlaceholder(insertion)
                            }
                        }
                        if !favorites.isLoaded {
                            Button(L10n.t("重新读取收藏夹")) { favorites.reload() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            Button { editingFolder = nil; showsEditor = true } label: {
                HStack(spacing: 10) {
                    KumoIcon("plus")
                        .frame(width: 18, height: 18)
                    Text(L10n.t("新建收藏夹"))
                    Spacer(minLength: 0)
                    if showsShortcutHints {
                        SidebarShortcutHintBadge(label: SidebarShortcutHints.newFolderLabel)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .buttonStyle(KumoButtonStyle(variant: .ghost))
            .help(L10n.t("新建收藏夹"))
            .accessibilityLabel(L10n.t("新建收藏夹"))
            .disabled(!favorites.isLoaded)

            SettingsLink {
                HStack(spacing: 10) {
                    KumoIcon("gear-six").frame(width: 18, height: 18)
                    Text(L10n.t("设置"))
                    Spacer(minLength: 0)
                    if showsShortcutHints {
                        SidebarShortcutHintBadge(label: SidebarShortcutHints.settingsLabel)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .buttonStyle(KumoButtonStyle(variant: .ghost))
            .help(L10n.t("设置"))
            .accessibilityLabel(L10n.t("设置"))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: 232)
        .background(KumoTheme.sidebar)
        .onChange(of: favorites.folders.map(\.id)) { _, _ in
            folderDropInsertion = nil
            videoDropTargetID = nil
        }
        .sheet(isPresented: $showsEditor) {
            FolderNameSheet(favorites: favorites, folder: editingFolder) { id in
                if editingFolder == nil { selectFolder(id) }
            }
        }
        .alert(L10n.t("删除收藏夹？"), isPresented: Binding(
            get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }
        )) {
            Button(L10n.t("取消"), role: .cancel) { deletingFolder = nil }
            Button(L10n.t("删除"), role: .destructive) {
                if let folder = deletingFolder { favorites.deleteFolder(folder.id) }
                deletingFolder = nil
            }
        } message: {
            Text(L10n.t("将删除「\(deletingFolder?.name ?? "")」及其中的收藏记录，其他收藏夹中的视频不受影响。"))
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: FavoriteFolder, at index: Int) -> some View {
        let selected = selectedFolderID == folder.id
        let color = FavoriteFolderStyle.resolvedColorHex(folder.colorHex)
            .flatMap { Color(favoriteFolderHex: $0) } ?? KumoTheme.text
        let shortcutLabels = SidebarShortcutHints.labels(forFolderAt: index,
                                                         folderCount: favorites.folders.count)
        Button { selectFolder(folder.id) } label: {
            HStack(spacing: 10) {
                KumoIcon(FavoriteFolderStyle.resolvedIconName(for: folder), size: 18)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(color)
                Text(folder.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsShortcutHints {
                    HStack(spacing: 4) {
                        ForEach(shortcutLabels, id: \.self) { label in
                            SidebarShortcutHintBadge(label: label, emphasized: selected)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: folderRowHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedFolderID == folder.id || hoveredFolderID == folder.id || videoDropTargetID == folder.id
                    ? KumoTheme.tint : .clear,
                    in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
        .overlay {
            if videoDropTargetID == folder.id {
                RoundedRectangle(cornerRadius: KumoTheme.radiusSmall)
                    .strokeBorder(KumoTheme.brand, lineWidth: 2)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredFolderID = folder.id
            } else if hoveredFolderID == folder.id {
                hoveredFolderID = nil
            }
        }
        .onDrag {
            YootubeDragPayload.folder(folder.id).itemProvider()
        }
        .onDrop(of: YootubeDragPayload.supportedContentTypes,
                delegate: FavoriteFolderDropDelegate(targetFolderID: folder.id,
                                                     rowHeight: folderRowHeight,
                                                     folderInsertion: $folderDropInsertion,
                                                     videoDropTargetID: $videoDropTargetID,
                                                     favorites: favorites))
        .accessibilityLabel(L10n.t("打开收藏夹 \(folder.name)"))
        .accessibilityHint(L10n.t("可拖动调整顺序，也可接收拖入的视频"))
        .contextMenu {
            Button { editingFolder = folder; showsEditor = true } label: {
                KumoLabel(L10n.t("编辑收藏夹"), icon: "pencil-simple")
            }
            Button(role: .destructive) { deletingFolder = folder } label: {
                KumoLabel(L10n.t("删除收藏夹…"), icon: "trash")
            }
        }
    }

    private func folderInsertionPlaceholder(_ insertion: FolderDropInsertion) -> some View {
        RoundedRectangle(cornerRadius: KumoTheme.radiusSmall)
            .fill(KumoTheme.tint)
            .frame(maxWidth: .infinity, minHeight: folderRowHeight, maxHeight: folderRowHeight)
            .onDrop(of: [.yootubeFolderDragPayload],
                    delegate: FolderInsertionDropDelegate(insertion: insertion,
                                                          activeInsertion: $folderDropInsertion,
                                                          favorites: favorites))
            .accessibilityHidden(true)
    }
}

private struct FolderDropInsertion: Equatable {
    let targetFolderID: UUID
    let placeAfter: Bool
}

private struct FavoriteFolderDropDelegate: DropDelegate {
    let targetFolderID: UUID
    let rowHeight: CGFloat
    @Binding var folderInsertion: FolderDropInsertion?
    @Binding var videoDropTargetID: UUID?
    let favorites: FavoritesStore

    func validateDrop(info: DropInfo) -> Bool {
        folderProvider(in: info) != nil || videoProvider(in: info) != nil
    }

    func dropEntered(info: DropInfo) {
        updateFeedback(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateFeedback(for: info)
        if folderProvider(in: info) != nil { return DropProposal(operation: .move) }
        if videoProvider(in: info) != nil { return DropProposal(operation: .copy) }
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        if videoDropTargetID == targetFolderID { videoDropTargetID = nil }
        if folderInsertion?.targetFolderID == targetFolderID { folderInsertion = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let provider = folderProvider(in: info) {
            let placeAfter = folderInsertion.flatMap {
                $0.targetFolderID == targetFolderID ? $0.placeAfter : nil
            } ?? (info.location.y >= rowHeight / 2)
            folderInsertion = nil
            videoDropTargetID = nil
            loadPayload(from: provider, contentType: .yootubeFolderDragPayload) { payload in
                guard let sourceID = payload.sourceFolderID else { return }
                _ = favorites.moveFolder(sourceID, relativeTo: targetFolderID, placeAfter: placeAfter)
            }
            return true
        }
        if let provider = videoProvider(in: info) {
            folderInsertion = nil
            videoDropTargetID = nil
            loadPayload(from: provider, contentType: .yootubeVideoDragPayload) { payload in
                guard let video = payload.favoriteVideo() else { return }
                _ = favorites.add(video, to: targetFolderID)
            }
            return true
        }
        return false
    }

    private func updateFeedback(for info: DropInfo) {
        if folderProvider(in: info) != nil {
            videoDropTargetID = nil
            folderInsertion = FolderDropInsertion(targetFolderID: targetFolderID,
                                                   placeAfter: info.location.y >= rowHeight / 2)
        } else if videoProvider(in: info) != nil {
            folderInsertion = nil
            videoDropTargetID = targetFolderID
        }
    }

    private func folderProvider(in info: DropInfo) -> NSItemProvider? {
        info.itemProviders(for: [.yootubeFolderDragPayload]).first
    }

    private func videoProvider(in info: DropInfo) -> NSItemProvider? {
        info.itemProviders(for: [.yootubeVideoDragPayload]).first
    }
}

private struct FolderInsertionDropDelegate: DropDelegate {
    let insertion: FolderDropInsertion
    @Binding var activeInsertion: FolderDropInsertion?
    let favorites: FavoritesStore

    func validateDrop(info: DropInfo) -> Bool {
        provider(in: info) != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        activeInsertion = insertion
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if activeInsertion == insertion { activeInsertion = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = provider(in: info) else { return false }
        activeInsertion = nil
        loadPayload(from: provider, contentType: .yootubeFolderDragPayload) { payload in
            guard let sourceID = payload.sourceFolderID else { return }
            _ = favorites.moveFolder(sourceID, relativeTo: insertion.targetFolderID,
                                     placeAfter: insertion.placeAfter)
        }
        return true
    }

    private func provider(in info: DropInfo) -> NSItemProvider? {
        info.itemProviders(for: [.yootubeFolderDragPayload]).first
    }
}

private func loadPayload(from provider: NSItemProvider, contentType: UTType,
                         completion: @escaping @MainActor @Sendable (YootubeDragPayload) -> Void) {
    provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
        guard let data else { return }
        Task { @MainActor in
            guard let payload = try? JSONDecoder().decode(YootubeDragPayload.self, from: data) else { return }
            completion(payload)
        }
    }
}

enum SidebarShortcutHints {
    static let homeLabel = "1"
    static let newFolderLabel = "N"
    static let settingsLabel = ","

    static func labels(forFolderAt index: Int, folderCount: Int) -> [String] {
        guard index >= 0, index < folderCount else { return [] }
        var labels: [String] = []
        if index < 7 { labels.append(String(index + 2)) }
        if folderCount >= 9, index == folderCount - 1 { labels.append("9") }
        return labels
    }
}

private struct SidebarShortcutHintBadge: View {
    let label: String
    var emphasized = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(KumoTheme.subtle)
            .frame(minWidth: 20, minHeight: 20)
            .background(emphasized ? KumoTheme.selectedShortcut : KumoTheme.tint,
                        in: RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}

struct FolderNameSheet: View {
    @ObservedObject var favorites: FavoritesStore
    var folder: FavoriteFolder? = nil
    var didSave: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIconName = FavoriteFolderStyle.defaultIconName
    @State private var selectedColorHex = FavoriteFolderStyle.defaultColorHex
    @FocusState private var focused: Bool

    private let iconColumns = Array(repeating: GridItem(.fixed(44), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(folder == nil ? L10n.t("新建收藏夹") : L10n.t("编辑收藏夹")).font(.headline)
            TextField(L10n.t("收藏夹名称"), text: $name).textFieldStyle(KumoInputStyle()).focused($focused).onSubmit(save)
            if !name.isEmpty, let error = favorites.nameError(name, excluding: folder?.id) {
                Text(L10n.t(error)).font(.caption).foregroundStyle(KumoTheme.subtle)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("图标")).font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 10) {
                    ForEach(FavoriteFolderStyle.iconOptions) { option in
                        let selected = selectedIconName == option.id
                        Button { selectedIconName = option.id } label: {
                            KumoIcon(option.id, size: 18)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(selected ? selectedColor : KumoTheme.text)
                                .background(selected ? selectedColor.opacity(0.14) : KumoTheme.base,
                                            in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                                .overlay(RoundedRectangle(cornerRadius: KumoTheme.radiusSmall)
                                    .strokeBorder(selected ? selectedColor : KumoTheme.line,
                                                  lineWidth: selected ? 2 : 1))
                                .contentShape(RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                        .accessibilityLabel(L10n.t("图标：\(option.title)"))
                        .accessibilityValue(selected ? L10n.t("已选择") : L10n.t("未选择"))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("颜色")).font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 6) {
                    ForEach(FavoriteFolderStyle.colorOptions) { option in
                        let selected = selectedColorHex == option.hex
                        let color = Color(favoriteFolderHex: option.hex) ?? KumoTheme.brand
                        Button { selectedColorHex = option.hex } label: {
                            ZStack {
                                if selected {
                                    Circle().stroke(color, lineWidth: 2).frame(width: 40, height: 40)
                                }
                                Circle().fill(color).frame(width: 32, height: 32)
                                if selected {
                                    KumoIcon("check", size: 15)
                                        .foregroundStyle(option.usesDarkCheckmark ? KumoTheme.ink.opacity(0.78) : KumoTheme.bodyOnDark)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                        .accessibilityLabel(L10n.t("颜色：\(option.title)"))
                        .accessibilityValue(selected ? L10n.t("已选择") : L10n.t("未选择"))
                    }
                }
            }

            if let error = favorites.errorMessage {
                Text(L10n.t(error)).font(.caption).foregroundStyle(KumoTheme.subtle)
            }
            HStack {
                Spacer()
                Button(L10n.t("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("保存"), action: save)
                    .buttonStyle(KumoButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(favorites.nameError(name, excluding: folder?.id) != nil)
            }
        }
        .padding(24).frame(width: 372)
        .background(KumoTheme.canvas).foregroundStyle(KumoTheme.text)
        .buttonStyle(KumoButtonStyle())
        .onAppear {
            name = folder?.name ?? ""
            selectedIconName = folder.map(FavoriteFolderStyle.resolvedIconName(for:)) ?? FavoriteFolderStyle.defaultIconName
            selectedColorHex = FavoriteFolderStyle.resolvedColorHex(folder?.colorHex) ?? FavoriteFolderStyle.defaultColorHex
            focused = true
        }
    }

    private var selectedColor: Color {
        Color(favoriteFolderHex: selectedColorHex) ?? KumoTheme.brand
    }

    private func save() {
        guard favorites.nameError(name, excluding: folder?.id) == nil else { return }
        if let folder {
            if favorites.updateFolder(folder.id, name: name, iconName: selectedIconName,
                                      colorHex: selectedColorHex) {
                didSave(folder.id)
                dismiss()
            }
        } else if let id = favorites.createFolder(named: name, iconName: selectedIconName,
                                                  colorHex: selectedColorHex) {
            didSave(id)
            dismiss()
        }
    }
}

private extension Color {
    init?(favoriteFolderHex hex: String) {
        guard hex.count == 7, hex.first == "#",
              let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

struct FavoritePicker: View {
    @ObservedObject var favorites: FavoritesStore
    let video: FavoriteVideo
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID>
    @State private var showsNewFolder = false
    @State private var hoveredFolderID: UUID?

    init(favorites: FavoritesStore, video: FavoriteVideo) {
        self.favorites = favorites
        self.video = video
        _selection = State(initialValue: Set(favorites.folders.filter { $0.videos.contains { $0.id == video.id } }.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.t("保存到收藏夹")).font(.headline)
            Text(video.title).font(.callout).foregroundStyle(KumoTheme.subtle).lineLimit(2)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(favorites.folders) { folder in
                        let selected = selection.contains(folder.id)
                        let color = FavoriteFolderStyle.resolvedColorHex(folder.colorHex)
                            .flatMap { Color(favoriteFolderHex: $0) } ?? KumoTheme.text
                        Button {
                            if selected { selection.remove(folder.id) } else { selection.insert(folder.id) }
                        } label: {
                            HStack(spacing: 12) {
                                KumoIcon(FavoriteFolderStyle.resolvedIconName(for: folder), size: 18)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(color)
                                Text(folder.name).lineLimit(2)
                                Spacer(minLength: 12)
                                if selected {
                                    KumoIcon("check", size: 17)
                                        .foregroundStyle(KumoTheme.brand)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(selected || hoveredFolderID == folder.id ? KumoTheme.tint : .clear,
                                    in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
                        .onHover { hovering in
                            if hovering {
                                hoveredFolderID = folder.id
                            } else if hoveredFolderID == folder.id {
                                hoveredFolderID = nil
                            }
                        }
                        .accessibilityLabel(folder.name)
                        .accessibilityValue(selected ? L10n.t("已选择") : L10n.t("未选择"))
                    }
                }
                .frame(maxWidth: .infinity)
            }.frame(maxHeight: 240)
            if let error = favorites.errorMessage {
                Text(L10n.t(error)).font(.caption).foregroundStyle(KumoTheme.subtle)
            }
            HStack {
                Button(L10n.t("新建收藏夹")) { showsNewFolder = true }
                Spacer()
                Button(L10n.t("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("保存")) {
                    if favorites.setMembership(for: video, folderIDs: selection) { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .buttonStyle(KumoButtonStyle(variant: .primary))
            }
        }
        .padding(24).frame(width: 400)
        .background(KumoTheme.canvas).foregroundStyle(KumoTheme.text)
        .buttonStyle(KumoButtonStyle())
        .sheet(isPresented: $showsNewFolder) {
            FolderNameSheet(favorites: favorites) { selection.insert($0) }
        }
    }
}
