import XCTest
@testable import Yootube

final class LocalizationTests: XCTestCase {
    private var previousLanguage: String?

    override func setUp() {
        super.setUp()
        previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
    }

    override func tearDown() {
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
        }
        super.tearDown()
    }

    func testEnglishStaticAndDynamicStrings() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)

        XCTAssertEqual(L10n.t("首页"), "Home")
        XCTAssertEqual(L10n.t("12 个视频"), "12 videos")
        XCTAssertEqual(L10n.t("1 个视频"), "1 video")
        XCTAssertEqual(L10n.t("打开 Example 的频道"), "Open Example's channel")
        XCTAssertEqual(L10n.t("1080p（高清，有声音）"), "1080p (HD, with audio)")
        XCTAssertEqual(L10n.t("封面、头像和横幅 · 已使用 24 MB / 300 MB"),
                       "Thumbnails, avatars, and banners · 24 MB / 300 MB")
    }

    func testSimplifiedChineseIsTheDefaultSourceLanguage() {
        UserDefaults.standard.set(AppLanguage.zhHans.rawValue, forKey: AppLanguage.defaultsKey)

        XCTAssertEqual(L10n.t("首页"), "首页")
        XCTAssertEqual(L10n.t("12 个视频"), "12 个视频")
        XCTAssertEqual(L10n.t("The local Invidious runtime is incomplete. Reinstall Yootube."),
                       "本地 Invidious 运行组件不完整，请重新安装 Yootube。")
        XCTAssertEqual(L10n.t("Save"), "Save")
    }

    func testTraditionalChineseUsesLocalizedInterfaceAndPreservesNames() {
        UserDefaults.standard.set(AppLanguage.zhHant.rawValue, forKey: AppLanguage.defaultsKey)

        XCTAssertEqual(L10n.t("设置"), "設定")
        XCTAssertEqual(L10n.t("视频缓存"), "影片快取")
        XCTAssertEqual(L10n.t("12 个视频"), "12 個影片")
        XCTAssertEqual(L10n.t("打开收藏夹 Work"), "開啟收藏夾 Work")
        XCTAssertEqual(L10n.t("General"), "通用")
    }

    func testJapaneseUsesLocalizedInterfaceAndDynamicLabels() {
        UserDefaults.standard.set(AppLanguage.japanese.rawValue, forKey: AppLanguage.defaultsKey)

        XCTAssertEqual(L10n.t("设置"), "設定")
        XCTAssertEqual(L10n.t("数据与缓存"), "データとキャッシュ")
        XCTAssertEqual(L10n.t("12 个视频"), "12 件の動画")
        XCTAssertEqual(L10n.t("打开收藏夹 Work"), "フォルダを開く: Work")
        XCTAssertEqual(L10n.t("1080p（本地缓存）"), "1080p（ローカルキャッシュ）")
        XCTAssertEqual(L10n.t("General"), "一般")
    }

    func testLanguageOwnsEveryExternalLocaleIdentifier() {
        XCTAssertEqual(AppLanguage.zhHans.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.zhHans.invidiousLanguageCode, "zh-CN")
        XCTAssertEqual(AppLanguage.zhHans.acceptLanguageHeader, "zh-CN,zh;q=0.9")
        XCTAssertEqual(AppLanguage.zhHans.playerLanguageCode, "zh-Hans")

        XCTAssertEqual(AppLanguage.zhHant.localeIdentifier, "zh-Hant")
        XCTAssertEqual(AppLanguage.zhHant.invidiousLanguageCode, "zh-TW")
        XCTAssertEqual(AppLanguage.zhHant.acceptLanguageHeader, "zh-TW,zh-Hant;q=0.9,zh;q=0.8")
        XCTAssertEqual(AppLanguage.zhHant.playerLanguageCode, "zh-Hant")

        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.english.invidiousLanguageCode, "en-US")
        XCTAssertEqual(AppLanguage.english.acceptLanguageHeader, "en-US,en;q=0.9")
        XCTAssertEqual(AppLanguage.english.playerLanguageCode, "en")

        XCTAssertEqual(AppLanguage.japanese.localeIdentifier, "ja")
        XCTAssertEqual(AppLanguage.japanese.invidiousLanguageCode, "ja")
        XCTAssertEqual(AppLanguage.japanese.acceptLanguageHeader, "ja-JP,ja;q=0.9")
        XCTAssertEqual(AppLanguage.japanese.playerLanguageCode, "ja")
    }
}
