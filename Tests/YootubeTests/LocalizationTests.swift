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

    func testLanguageOwnsEveryExternalLocaleIdentifier() {
        XCTAssertEqual(AppLanguage.zhHans.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.zhHans.invidiousLanguageCode, "zh-CN")
        XCTAssertEqual(AppLanguage.zhHans.acceptLanguageHeader, "zh-CN,zh;q=0.9")
        XCTAssertEqual(AppLanguage.zhHans.playerLanguageCode, "zh-Hans")

        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.english.invidiousLanguageCode, "en-US")
        XCTAssertEqual(AppLanguage.english.acceptLanguageHeader, "en-US,en;q=0.9")
        XCTAssertEqual(AppLanguage.english.playerLanguageCode, "en")
    }
}
