import Foundation
import CoreFoundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans
    case zhHant
    case english
    case japanese

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }
    var localeIdentifier: String {
        switch self {
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        case .english: "en"
        case .japanese: "ja"
        }
    }
    var locale: Locale { Locale(identifier: localeIdentifier) }
    var invidiousLanguageCode: String {
        switch self {
        case .zhHans: "zh-CN"
        case .zhHant: "zh-TW"
        case .english: "en-US"
        case .japanese: "ja"
        }
    }
    var acceptLanguageHeader: String {
        switch self {
        case .zhHans: "zh-CN,zh;q=0.9"
        case .zhHant: "zh-TW,zh-Hant;q=0.9,zh;q=0.8"
        case .english: "en-US,en;q=0.9"
        case .japanese: "ja-JP,ja;q=0.9"
        }
    }
    var playerLanguageCode: String { localeIdentifier }
    var title: String {
        switch self {
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }
    static var current: AppLanguage {
        guard let value = UserDefaults.standard.string(forKey: defaultsKey),
              let language = AppLanguage(rawValue: value) else { return .zhHans }
        return language
    }
}

enum L10n {
    static func t(_ source: String) -> String {
        switch AppLanguage.current {
        case .zhHans:
            return chineseByEnglish[source] ?? translateDynamicToChinese(source)
        case .english:
            if let translated = english[source] { return translated }
            return translateDynamic(source)
        case .zhHant, .japanese:
            let chineseSource = chineseByEnglish[source] ?? translateDynamicToChinese(source)
            if AppLanguage.current == .zhHant {
                return traditional[chineseSource] ?? translateDynamicToTraditional(chineseSource)
            }
            return JapaneseTranslations.strings[chineseSource] ?? translateDynamicToJapanese(chineseSource)
        }
    }

    private static let traditional: [String: String] = Dictionary(
        uniqueKeysWithValues: english.keys.map { ($0, traditionalize($0)) }
    )

    private static func traditionalize(_ source: String) -> String {
        let converted = NSMutableString(string: source)
        CFStringTransform(converted, nil, "Hans-Hant" as CFString, false)
        return (converted as String)
            .replacingOccurrences(of: "設置", with: "設定")
            .replacingOccurrences(of: "視頻", with: "影片")
            .replacingOccurrences(of: "緩存", with: "快取")
            .replacingOccurrences(of: "播放列表", with: "播放清單")
            .replacingOccurrences(of: "數據", with: "資料")
            .replacingOccurrences(of: "本地", with: "本機")
    }

    // Runtime status and error text can outlive a language switch. Translate it
    // back only when the English phrase identifies one Chinese source exactly.
    private static let chineseByEnglish: [String: String] = {
        let grouped = Dictionary(grouping: english.keys, by: { english[$0]! })
        return grouped.compactMapValues { sources in
            sources.count == 1 ? sources[0] : nil
        }
    }()

    private static func translateDynamic(_ source: String) -> String {
        let suffixes: [(String, String, String)] = [
            (" 个最新视频", " latest video", " latest videos"),
            (" 个已缓存视频", " cached video", " cached videos"),
            (" 个收藏夹", " folder", " folders"),
            (" 个频道", " channel", " channels"),
            (" 个视频", " video", " videos"),
            (" 位订阅者", " subscriber", " subscribers"),
            (" 次观看", " view", " views")
        ]
        for (suffix, singular, plural) in suffixes where source.hasSuffix(suffix) {
            let count = String(source.dropLast(suffix.count))
            return count + (numericValue(count) == 1 ? singular : plural)
        }

        let prefixes: [(String, String)] = [
            ("打开收藏夹 ", "Open folder "),
            ("打开频道 ", "Open channel "),
            ("播放收藏 ", "Play saved video "),
            ("播放 ", "Play "),
            ("从此收藏夹移除 ", "Remove from this folder: "),
            ("订阅 ", "Subscribe to "),
            ("图标：", "Icon: "),
            ("颜色：", "Color: "),
            ("外观：", "Appearance: "),
            ("画中画启动失败：", "Picture in Picture failed to start: "),
            ("画中画视频加载失败：", "Picture in Picture video failed to load: "),
            ("本地端口 ", "Local port "),
            ("本地占用 ", "Local storage used: "),
            ("已使用 ", "Used "),
            ("已缓存 ", "Cached ")
        ]
        for (prefix, replacement) in prefixes where source.hasPrefix(prefix) {
            let remainder = String(source.dropFirst(prefix.count))
            if prefix == "本地端口 " {
                return "Local port " + remainder
                    .replacingOccurrences(of: " 已被其他进程占用。请关闭占用该端口的程序后重试。",
                                          with: " is already in use. Close the process using it and try again.")
            }
            if prefix == "已使用 " {
                return "Used " + remainder.replacingOccurrences(of: "，上限 ", with: ", limit ")
            }
            if prefix == "已缓存 " {
                return "Cached " + remainder
                    .replacingOccurrences(of: "，可更换清晰度或删除本地缓存", with: "; choose another quality or remove the local copy")
                    .replacingOccurrences(of: " 个视频，共 ", with: " videos, ")
            }
            return replacement + remainder
        }

        let imageCachePrefix = "封面、头像和横幅 · 已使用 "
        if source.hasPrefix(imageCachePrefix) {
            return "Thumbnails, avatars, and banners · " + source.dropFirst(imageCachePrefix.count)
        }
        if source.contains(" 个视频 · ") {
            let count = String(source.prefix { !$0.isWhitespace })
            return source.replacingOccurrences(of: " 个视频 · ",
                                               with: numericValue(count) == 1 ? " video · " : " videos · ")
        }

        if source.hasPrefix("打开 "), source.hasSuffix(" 的频道") {
            return "Open " + source.dropFirst(3).dropLast(4) + "'s channel"
        }
        if source.hasPrefix("取消订阅 ") {
            return "Unsubscribe from " + source.dropFirst(5)
        }
        if source.hasPrefix("将删除「"),
           let end = source.range(of: "」及其中的收藏记录，其他收藏夹中的视频不受影响。") {
            let name = source[source.index(source.startIndex, offsetBy: 4)..<end.lowerBound]
            return "Delete “\(name)” and its saved videos. Videos in other folders will not be affected."
        }
        if source.hasPrefix("将删除 "), source.contains(" 个已缓存视频") {
            let count = source.dropFirst(4).split(separator: " ").first ?? "0"
            return "This will delete \(count) cached videos. Folders, subscriptions, and watch history will not be affected."
        }
        if source.hasSuffix("p（高清，有声音）") {
            return source.replacingOccurrences(of: "（高清，有声音）", with: " (HD, with audio)")
        }
        if source.hasSuffix("p（有声音）") {
            return source.replacingOccurrences(of: "（有声音）", with: " (with audio)")
        }
        if source.hasSuffix("p（本地缓存）") {
            return source.replacingOccurrences(of: "（本地缓存）", with: " (local cache)")
        }
        if source.hasSuffix(" 启动后立即退出。请查看设置中的日志目录。") {
            return source.replacingOccurrences(of: " 启动后立即退出。请查看设置中的日志目录。",
                                               with: " exited immediately after launch. Check the log folder in Settings.")
        }
        if source.hasSuffix(" 启动超时。请查看设置中的日志目录。") {
            return source.replacingOccurrences(of: " 启动超时。请查看设置中的日志目录。",
                                               with: " timed out while starting. Check the log folder in Settings.")
        }
        if let range = source.range(of: " 启动失败：") {
            return String(source[..<range.lowerBound]) + " failed to start: " + String(source[range.upperBound...])
        }
        if source.hasPrefix("无法读取本地收藏夹，原文件已保留。请检查文件后重新读取。\n") {
            return source.replacingOccurrences(of: "无法读取本地收藏夹，原文件已保留。请检查文件后重新读取。\n",
                                               with: "The local folders could not be read. The original file was preserved. Check it, then reload.\n")
        }
        if source.hasPrefix("无法读取本地订阅，原文件已保留。请检查文件后重新读取。\n") {
            return source.replacingOccurrences(of: "无法读取本地订阅，原文件已保留。请检查文件后重新读取。\n",
                                               with: "The local subscriptions could not be read. The original file was preserved. Check it, then reload.\n")
        }
        return source
    }

    private static func translateDynamicToChinese(_ source: String) -> String {
        if source.hasSuffix(" exited immediately after launch. Check the log folder in Settings.") {
            return source.replacingOccurrences(of: " exited immediately after launch. Check the log folder in Settings.",
                                               with: " 启动后立即退出。请查看设置中的日志目录。")
        }
        if source.hasSuffix(" timed out while starting. Check the log folder in Settings.") {
            return source.replacingOccurrences(of: " timed out while starting. Check the log folder in Settings.",
                                               with: " 启动超时。请查看设置中的日志目录。")
        }
        if let range = source.range(of: " failed to start: ") {
            return String(source[..<range.lowerBound]) + " 启动失败：" + String(source[range.upperBound...])
        }
        if source.hasPrefix("Picture in Picture failed to start: ") {
            return source.replacingOccurrences(of: "Picture in Picture failed to start: ", with: "画中画启动失败：")
        }
        if source.hasPrefix("Picture in Picture video failed to load: ") {
            return source.replacingOccurrences(of: "Picture in Picture video failed to load: ", with: "画中画视频加载失败：")
        }
        if source.hasPrefix("The local folders could not be read. The original file was preserved. Check it, then reload.\n") {
            return source.replacingOccurrences(of: "The local folders could not be read. The original file was preserved. Check it, then reload.\n",
                                               with: "无法读取本地收藏夹，原文件已保留。请检查文件后重新读取。\n")
        }
        if source.hasPrefix("The local subscriptions could not be read. The original file was preserved. Check it, then reload.\n") {
            return source.replacingOccurrences(of: "The local subscriptions could not be read. The original file was preserved. Check it, then reload.\n",
                                               with: "无法读取本地订阅，原文件已保留。请检查文件后重新读取。\n")
        }
        return source
    }

    private static func numericValue(_ source: String) -> Int? {
        Int(source.replacingOccurrences(of: ",", with: ""))
    }

    private static func translateDynamicToTraditional(_ source: String) -> String {
        let suffixes: [(String, String)] = [
            (" 个最新视频", " 個最新影片"), (" 个已缓存视频", " 個已快取影片"),
            (" 个收藏夹", " 個收藏夾"), (" 个频道", " 個頻道"),
            (" 个视频", " 個影片"), (" 位订阅者", " 位訂閱者"),
            (" 次观看", " 次觀看")
        ]
        for (suffix, replacement) in suffixes where source.hasSuffix(suffix) {
            return String(source.dropLast(suffix.count)) + replacement
        }
        let prefixes: [(String, String)] = [
            ("打开收藏夹 ", "開啟收藏夾 "), ("打开频道 ", "開啟頻道 "),
            ("播放收藏 ", "播放收藏的影片 "), ("播放 ", "播放 "),
            ("从此收藏夹移除 ", "從此收藏夾移除 "),
            ("取消订阅 ", "取消訂閱 "), ("订阅 ", "訂閱 "),
            ("图标：", "圖示："), ("颜色：", "顏色："),
            ("外观：", "外觀：")
        ]
        for (prefix, replacement) in prefixes where source.hasPrefix(prefix) {
            let value = String(source.dropFirst(prefix.count))
            return replacement + (traditional[value] ?? value)
        }
        if source.hasPrefix("打开 "), source.hasSuffix(" 的频道") {
            return "開啟 " + source.dropFirst(3).dropLast(4) + " 的頻道"
        }
        if source.hasPrefix("将删除「"),
           let end = source.range(of: "」及其中的收藏记录，其他收藏夹中的视频不受影响。") {
            let name = source[source.index(source.startIndex, offsetBy: 4)..<end.lowerBound]
            return "將刪除「\(name)」及其中收藏的影片。其他收藏夾中的影片不受影響。"
        }
        return traditionalize(source)
    }

    private static func translateDynamicToJapanese(_ source: String) -> String {
        let suffixes: [(String, String)] = [
            (" 个最新视频", " 件の最新動画"), (" 个已缓存视频", " 件のキャッシュ済み動画"),
            (" 个收藏夹", " 個のフォルダ"), (" 个频道", " 件のチャンネル"),
            (" 个视频", " 件の動画"), (" 位订阅者", " 人の登録者"),
            (" 次观看", " 回再生")
        ]
        for (suffix, replacement) in suffixes where source.hasSuffix(suffix) {
            return String(source.dropLast(suffix.count)) + replacement
        }
        let prefixes: [(String, String)] = [
            ("打开收藏夹 ", "フォルダを開く: "), ("打开频道 ", "チャンネルを開く: "),
            ("播放收藏 ", "保存済み動画を再生: "), ("播放 ", "再生: "),
            ("从此收藏夹移除 ", "このフォルダから削除: "),
            ("取消订阅 ", "登録解除: "), ("订阅 ", "登録: "),
            ("图标：", "アイコン: "), ("颜色：", "色: "),
            ("外观：", "外観: "),
            ("画中画启动失败：", "ピクチャ・イン・ピクチャを開始できません: "),
            ("画中画视频加载失败：", "ピクチャ・イン・ピクチャの動画を読み込めません: "),
            ("本地占用 ", "ローカル使用量: ")
        ]
        for (prefix, replacement) in prefixes where source.hasPrefix(prefix) {
            let value = String(source.dropFirst(prefix.count))
            return replacement + (JapaneseTranslations.strings[value] ?? value)
        }
        if source.hasPrefix("打开 "), source.hasSuffix(" 的频道") {
            return "チャンネルを開く: " + source.dropFirst(3).dropLast(4)
        }
        if source.hasPrefix("封面、头像和横幅 · 已使用 ") {
            return "サムネイル、アバター、バナー · 使用量 " + source.dropFirst("封面、头像和横幅 · 已使用 ".count)
        }
        if source.contains(" 个视频 · ") {
            return source.replacingOccurrences(of: " 个视频 · ", with: " 件の動画 · ")
        }
        if source.hasPrefix("已使用 ") {
            return "使用量 " + source.dropFirst(4).replacingOccurrences(of: "，上限 ", with: "、上限 ")
        }
        if source.hasPrefix("已缓存 ") {
            return "キャッシュ済み: " + source.dropFirst(4)
                .replacingOccurrences(of: "，可更换清晰度或删除本地缓存", with: "。画質の変更やローカルキャッシュの削除ができます")
                .replacingOccurrences(of: " 个视频，共 ", with: " 件の動画、合計 ")
        }
        if source.hasPrefix("本地端口 ") {
            return "ローカルポート " + source.dropFirst(5)
                .replacingOccurrences(of: " 已被其他进程占用。请关闭占用该端口的程序后重试。", with: " は他のプロセスで使用中です。そのプロセスを終了してから再試行してください。")
        }
        if source.hasPrefix("将删除「"),
           let end = source.range(of: "」及其中的收藏记录，其他收藏夹中的视频不受影响。") {
            let name = source[source.index(source.startIndex, offsetBy: 4)..<end.lowerBound]
            return "「\(name)」とその保存済み動画を削除します。他のフォルダの動画には影響しません。"
        }
        if source.hasPrefix("将删除 "), source.contains(" 个已缓存视频") {
            let count = source.dropFirst(4).split(separator: " ").first ?? "0"
            return "キャッシュ済み動画を\(count)件削除します。フォルダ、登録チャンネル、視聴履歴には影響しません。"
        }
        let qualitySuffixes: [(String, String)] = [
            ("（高清，有声音）", "（高画質・音声あり）"),
            ("（有声音）", "（音声あり）"), ("（本地缓存）", "（ローカルキャッシュ）")
        ]
        for (suffix, replacement) in qualitySuffixes where source.hasSuffix(suffix) {
            return String(source.dropLast(suffix.count)) + replacement
        }
        let errorSuffixes: [(String, String)] = [
            (" 启动后立即退出。请查看设置中的日志目录。", " は起動直後に終了しました。設定のログフォルダを確認してください。"),
            (" 启动超时。请查看设置中的日志目录。", " の起動がタイムアウトしました。設定のログフォルダを確認してください。")
        ]
        for (suffix, replacement) in errorSuffixes where source.hasSuffix(suffix) {
            return String(source.dropLast(suffix.count)) + replacement
        }
        if let range = source.range(of: " 启动失败：") {
            return String(source[..<range.lowerBound]) + " を起動できませんでした: " + source[range.upperBound...]
        }
        let fileErrors: [(String, String)] = [
            ("无法读取本地收藏夹，原文件已保留。请检查文件后重新读取。\n", "ローカルフォルダを読み込めませんでした。元のファイルは保持されています。確認後に再読み込みしてください。\n"),
            ("无法读取本地订阅，原文件已保留。请检查文件后重新读取。\n", "ローカルの登録チャンネルを読み込めませんでした。元のファイルは保持されています。確認後に再読み込みしてください。\n")
        ]
        for (prefix, replacement) in fileErrors where source.hasPrefix(prefix) {
            return replacement + source.dropFirst(prefix.count)
        }
        return source
    }

    private static let english: [String: String] = [
        "书签": "Bookmark", "亮色": "Light", "人物": "People", "从此收藏夹移除": "Remove from this folder",
        "一个完全属于这台 Mac 的私密有序资料库。": "A private, organized library that lives entirely on your Mac.",
        "App 语言": "App Language", "通用": "General", "数据与缓存": "Data & Cache", "本地服务": "Local Services",
        "语言": "Language", "更改会立即应用到所有窗口。": "Changes apply to every window immediately.",
        "键盘": "Keyboard", "本地数据": "Local Data", "视频缓存不会包含在备份文件中。": "Video cache files are not included in backups.",
        "频道订阅、收藏夹、播放列表和最近观看只保存在此 Mac。": "Subscriptions, folders, playlists, and watch history stay on this Mac.",
        "清除": "Clear", "运行状态": "Status", "服务地址": "Service Address", "打开日志目录": "Open Logs Folder",
        "Invidious、PostgreSQL 和视频代理随 Yootube 启动，只监听此 Mac 的回环地址。出站连接使用 macOS 系统代理。": "Invidious, PostgreSQL, and the video proxy start with Yootube and listen only on this Mac. Outbound connections use the macOS system proxy.",
        "Yootube 本地数据已保存到你选择的位置。": "Yootube data was saved to the selected location.",
        "画中画启动超时，请稍后重试。": "Picture in Picture timed out. Try again shortly.", "或": "or",
        "保存": "Save", "保存到收藏夹": "Save to Folders", "保存到本地收藏夹": "Save to a Local Folder",
        "全球": "Global", "全部": "All", "关闭": "Close", "切换外观": "Change appearance",
        "删除": "Delete", "删除收藏夹…": "Delete Folder…", "删除收藏夹？": "Delete Folder?",
        "删除本地缓存": "Remove Local Cache", "前进": "Forward", "刷新": "Refresh", "加载更多": "Load More",
        "加载更多评论": "Load More Comments", "加载评论": "Load Comments",
        "单键快捷键在输入文字时不会触发。": "Single-key shortcuts are disabled while typing.",
        "取消": "Cancel", "取消订阅": "Unsubscribe",
        "只保存你在视频页主动选择的视频。再次打开时优先从本地播放；1080p 视频可能占用数百 MB，缓存不会自动清理。": "Only videos you choose on a video page are saved. They play locally next time; 1080p videos may use hundreds of MB and are not removed automatically.",
        "可拖到左侧收藏夹": "Drag to a folder in the sidebar",
        "可拖动调整顺序，也可接收拖入的视频": "Drag to reorder, or drop videos here",
        "合并会保留本机内容并去重；覆盖会用备份内容替换本机收藏夹、订阅和最近观看。导入前都会自动备份现有数据。": "Merge keeps local items and removes duplicates. Replace overwrites local folders, subscriptions, and watch history. Existing data is backed up before either action.",
        "合并数据": "Merge Data", "名称不能超过 80 个字符": "Names can contain up to 80 characters",
        "后退": "Back", "启动中": "Starting", "启动失败": "Failed to Start", "喜欢": "Likes",
        "回到首页": "Go Home", "图标": "Icon", "图片缓存": "Image Cache",
        "在视频详情页点击「收藏」，选择这个收藏夹": "On a video page, choose Save and select this folder.",
        "地址": "Address", "备份中的收藏夹数据无效，未修改本地数据。": "The folder data in the backup is invalid. Local data was not changed.",
        "备份中的频道订阅无效，未修改本地数据。": "The subscriptions in the backup are invalid. Local data was not changed.",
        "备份文件无效或版本不受支持，本地数据未修改。": "The backup is invalid or uses an unsupported version. Local data was not changed.",
        "复制 YouTube 链接": "Copy YouTube Link", "外观": "Appearance", "好": "OK", "字幕": "Captions",
        "导入备份": "Import Backup", "导入失败": "Import Failed",
        "导入失败，已尝试恢复导入前的数据。": "Import failed. Yootube attempted to restore the previous data.",
        "导入完成": "Import Complete", "导出备份": "Export Backup", "导出失败": "Export Failed",
        "导出完成": "Export Complete", "导出频道订阅、收藏夹与最近观看": "Export subscriptions, folders, and watch history",
        "导航": "Navigation", "展开/收起侧栏": "Toggle Sidebar", "展开侧栏": "Show Sidebar",
        "展开简介": "Show Description", "已复制": "Copied", "已复制 YouTube 链接": "YouTube link copied",
        "已收藏": "Saved", "已有同名收藏夹": "A folder with this name already exists", "已订阅": "Subscribed",
        "已选择": "Selected", "当前 Mac 不支持画中画。": "This Mac does not support Picture in Picture.",
        "当前播放环境无法创建画中画窗口。": "The current playback environment cannot create a Picture in Picture window.",
        "当前视频没有可用于画中画的兼容播放源。": "This video has no compatible source for Picture in Picture.",
        "当前视频没有可缓存的兼容格式": "This video has no compatible format to cache",
        "频道更新": "Channel Updates", "打开或关闭频道更新": "Show or Hide Channel Updates",
        "全部已读": "Mark all as read", "开启系统通知": "Enable System Notifications",
        "频道通知暂时无法读取": "Channel notifications are temporarily unavailable",
        "订阅频道有新视频时会显示在这里": "New videos from subscribed channels will appear here.",
        "无法读取频道通知，原文件已保留。": "Channel notifications could not be read. The original file was preserved.",
        "频道通知保存失败，此次更改未生效。": "Channel notifications could not be saved. The change was not applied.",
        "影院模式 / 播放器全屏": "Theater Mode / Player Full Screen", "打开或关闭左侧栏": "Show or Hide Sidebar",
        "打开数据目录": "Open Data Folder", "接着看": "Up Next", "提醒": "Alerts", "搜索": "Search",
        "搜索或粘贴 YouTube 链接": "Search or paste a YouTube link", "搜索结果": "Search Results",
        "播放": "Play", "播放列表": "Playlist", "播放列表中没有可保存的视频。": "This playlist has no videos to save.",
        "播放列表中没有视频": "No videos in this playlist", "播放器暂时未就绪，请稍后重试。": "The player is not ready yet. Try again shortly.",
        "播放器连接失败，请重试。": "The player could not connect. Try again.", "播放或暂停": "Play or Pause",
        "播放过的视频会出现在这里": "Videos you watch will appear here", "收藏": "Save", "收藏夹": "Folders",
        "收藏夹、频道订阅和最近观看已恢复。导入前的数据已自动备份。": "Folders, subscriptions, and watch history were restored. Previous data was backed up automatically.",
        "收藏夹保存失败，此次更改未生效。请检查磁盘空间和文件权限后重试。": "The folder could not be saved. Check disk space and file permissions, then try again.",
        "收藏夹名称": "Folder Name", "收藏夹暂时无法读取": "Folders are temporarily unavailable",
        "收藏夹样式无效。": "The folder style is invalid.", "收藏视频": "Save Video", "收起侧栏": "Hide Sidebar",
        "收起简介": "Hide Description", "数据保存在本地": "Data Stays on This Mac", "文件夹": "Folder",
        "新建收藏夹": "New Folder", "无法删除这个视频的本地缓存。": "The local cache for this video could not be removed.",
        "无法导入": "Cannot Import", "无法导出": "Cannot Export", "无法清除视频缓存": "Cannot Clear Video Cache",
        "无法识别这个频道。": "This channel could not be recognized.", "无法读取当前本地数据，原文件已保留。": "Current local data could not be read. The original files were preserved.",
        "日志": "Logs", "星标": "Star", "显示快捷键": "Show Shortcuts", "暂无相关推荐": "No recommendations yet",
        "暂无视频": "No Videos", "暂无评论": "No Comments", "暂时无法准备画中画，请稍后重试。": "Picture in Picture could not be prepared. Try again shortly.",
        "暂时无法获取视频数据，请稍后重试。": "Video data is temporarily unavailable. Try again shortly.",
        "暗色": "Dark", "最后一个收藏夹": "Last Folder", "最近观看": "Recently Watched", "未启动": "Not Running",
        "未选择": "Not Selected", "本地 Invidious": "Local Invidious",
        "本地 Invidious 运行组件不完整，请重新安装 Yootube。": "The local Invidious runtime is incomplete. Reinstall Yootube.",
        "本地收藏夹": "Local Folders", "本地服务暂时无法启动": "The local service could not start",
        "本地视频缓存已全部清除。": "The local video cache was cleared.", "本地订阅": "Local Subscriptions",
        "本地订阅暂时无法读取": "Local subscriptions are temporarily unavailable", "本机已有数据": "This Mac Already Has Data",
        "查看导航、收藏夹和视频播放快捷键，也可以随时按 ? 打开。": "View navigation, folder, and playback shortcuts. Press ? anytime to open this window.",
        "查看快捷键": "View Shortcuts", "橙红": "Orange Red", "橙色": "Orange", "正在准备播放…": "Preparing playback…",
        "正在准备本地服务…": "Preparing local services…", "正在准备视频播放…": "Preparing video playback…",
        "正在初始化本地数据库…": "Initializing the local database…", "正在加载推荐视频": "Loading recommended videos",
        "正在加载播放列表…": "Loading playlist…", "正在加载视频详情": "Loading video details",
        "正在加载频道": "Loading channel", "正在加载频道…": "Loading channel…", "正在启动 Invidious…": "Starting Invidious…",
        "正在启动 PostgreSQL…": "Starting PostgreSQL…", "正在启动视频代理…": "Starting video proxy…", "正在搜索…": "Searching…",
        "没有找到结果": "No Results", "洋红": "Magenta", "浅灰": "Light Gray", "深灰": "Dark Gray",
        "清理完成": "Cleanup Complete", "清除全部视频缓存": "Clear All Video Cache",
        "清除全部视频缓存？": "Clear All Video Cache?", "清除图片缓存": "Clear Image Cache",
        "清除视频缓存": "Clear Video Cache", "状态": "Status", "珊瑚红": "Coral", "私人": "Private",
        "科技": "Technology", "稍后观看": "Watch Later", "空格": "Space", "第 1–7 个收藏夹": "Folders 1–7",
        "粉红": "Pink", "紫色": "Purple", "红色": "Red", "绿色": "Green", "缓存": "Cache",
        "缓存中…": "Caching…", "缓存失败，磁盘可用空间不足。": "Caching failed because there is not enough disk space.",
        "缓存视频": "Cache Video", "缓存视频封面、频道头像与横幅，让再次打开页面时加载更快。视频内容使用下方独立的手动缓存。": "Caches thumbnails, channel avatars, and banners so pages load faster next time. Videos use the separate manual cache below.",
        "编程": "Programming", "编辑收藏夹": "Edit Folder", "编辑视频收藏": "Edit Saved Folders", "翠绿": "Emerald",
        "聚焦搜索": "Focus Search", "聚焦搜索（⌘F）": "Focus Search (⌘F)", "聚焦搜索（⌘K）": "Focus Search (⌘K)",
        "自动播放": "Autoplay", "蓝绿": "Teal", "蓝色": "Blue", "覆盖本机数据": "Replace Local Data",
        "观看": "Watch", "视频": "Videos", "视频代理": "Video Proxy", "视频播放": "Playback",
        "视频缓存": "Video Cache", "视频缓存失败，请检查网络和磁盘空间后重试。": "Video caching failed. Check your network and available disk space, then try again.",
        "订阅": "Subscribe", "订阅保存失败，此次更改未生效。请检查磁盘空间和文件权限后重试。": "The subscription could not be saved. Check disk space and file permissions, then try again.",
        "订阅并保存到本机": "Subscribe and save on this Mac", "订阅的频道": "Subscribed Channels",
        "订阅频道后会显示在这里": "Channels you subscribe to will appear here", "设置": "Settings", "评论": "Comments",
        "评论暂时无法加载，请重试。": "Comments could not be loaded. Try again.", "试试更简短或不同的关键词。": "Try a shorter or different search.",
        "请输入收藏夹名称": "Enter a folder name", "资讯": "News", "跟随系统": "System", "运行中": "Running",
        "返回": "Back", "返回主页": "Return Home", "返回首页": "Return Home",
        "选择 Yootube JSON 备份文件": "Choose a Yootube JSON backup file",
        "选择分辨率缓存到此 Mac，下次优先从本地播放": "Choose a resolution to cache on this Mac. Yootube will use the local copy next time.",
        "选择缓存清晰度": "Choose Cache Quality", "选择要保存到的收藏夹": "Choose folders for this video",
        "选择要保存在此 Mac 的视频分辨率。": "Choose the video resolution to save on this Mac.",
        "重启本地服务": "Restart Local Services", "重新加载详情": "Reload Details", "重新读取": "Reload",
        "重新读取收藏夹": "Reload Folders", "重试": "Try Again", "重试播放": "Retry Playback",
        "键盘快捷键": "Keyboard Shortcuts", "青柠": "Lime", "青色": "Cyan", "静音": "Mute", "靛蓝": "Indigo",
        "音乐": "Music", "页面暂时无法加载": "Page Unavailable", "频道": "Channels", "频道与订阅": "Channel & Subscription",
        "频道订阅、收藏夹与播放列表、最近观看都只保存在此 Mac。你可以导出一个 JSON 备份文件，并在其他 Mac 上导入恢复。视频缓存文件不会包含在备份中。": "Channel subscriptions, folders, playlists, and watch history stay on this Mac. Export a JSON backup to restore them on another Mac. Video cache files are not included.",
        "颜色": "Color", "首页": "Home", "黄色": "Yellow", "黑色": "Black"
    ]
}
