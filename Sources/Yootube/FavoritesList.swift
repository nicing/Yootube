import SwiftUI

struct FavoritesList: View {
    @ObservedObject var favorites: FavoritesStore
    let folder: FavoriteFolder
    let available: Bool
    let open: (FavoriteVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(folder.name).font(.system(size: 24, weight: .semibold))
                Spacer()
                Text(L10n.t("\(folder.videos.count) 个视频")).font(.caption).foregroundStyle(KumoTheme.subtle)
            }
            if !favorites.isLoaded {
                HStack {
                    Text(L10n.t("收藏夹暂时无法读取")).foregroundStyle(KumoTheme.subtle)
                    Button(L10n.t("重新读取")) { favorites.reload() }
                }.frame(maxWidth: .infinity, minHeight: 88)
            } else if folder.videos.isEmpty {
                HStack(spacing: 12) {
                    KumoIcon("bookmark-simple").font(.title3)
                    Text(L10n.t("在视频详情页点击「收藏」，选择这个收藏夹")).font(.callout)
                }
                .foregroundStyle(KumoTheme.subtle)
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                LazyVGrid(columns: nativeVideoCardColumns, alignment: .leading, spacing: 22) {
                    ForEach(folder.videos) { entry in
                        NativeVideoCard(videoID: entry.id, title: entry.title,
                                        author: entry.author, authorID: nil, metadata: nil,
                                        lengthSeconds: nil,
                                        thumbnailAvailable: available,
                                        relativeDate: entry.savedAt,
                                        removeAction: {
                                            favorites.remove(videoID: entry.id, from: folder.id)
                                        },
                                        removeAccessibilityLabel: L10n.t("从此收藏夹移除 \(entry.title)"),
                                        openVideo: { open(entry) },
                                        openChannel: { _ in })
                            .accessibilityLabel(L10n.t("播放收藏 \(entry.title)"))
                    }
                }
            }
        }
    }
}
