import WebKit
import XCTest
@testable import Yootube

@MainActor
final class PlayerSkinTests: XCTestCase {
    private func fixture(storedQuality: Int? = nil, blocksMenuClicks: Bool = false,
                         playbackHandler: (any WKScriptMessageHandler)? = nil) async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        if let playbackHandler {
            config.userContentController.add(playbackHandler, name: "detailPlayback")
        }
        config.userContentController.addUserScript(WKUserScript(source: PlayerSkin.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 405), configuration: config)
        let qualitySetup = storedQuality.map {
            "try { localStorage.setItem('yootube.player.qualityHeight', '\($0)'); } catch {}"
        } ?? "try { localStorage.removeItem('yootube.player.qualityHeight'); } catch {}"
        let clickInterceptor = blocksMenuClicks ? """
        ['pointerdown', 'mousedown', 'mouseup', 'click'].forEach(type => {
          window.addEventListener(type, event => {
            if (event.target instanceof Element && event.target.closest('.video-player__menu-button')) {
              event.stopImmediatePropagation();
            }
          }, true);
        });
        """ : ""
        web.loadHTMLString(
            Self.html
                .replacingOccurrences(of: "/* QUALITY_PREFERENCE */", with: qualitySetup)
                .replacingOccurrences(of: "/* MENU_CLICK_INTERCEPTOR */", with: clickInterceptor),
            baseURL: URL(string: "https://yootube-player.test")
        )
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!document.querySelector('.video-player__controls')")) as? Bool == true { return web }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Player controls did not initialize in WebKit")
        return web
    }

    private func nativeFixture() async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(
            source: PlayerSkin.script, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 405), configuration: config)
        web.loadHTMLString(Self.nativeHTML, baseURL: URL(string: "https://yootube-cache.test"))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!document.querySelector('.video-player__controls')")) as? Bool == true {
                return web
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Native cached player controls did not initialize in WebKit")
        return web
    }

    func testCachedPlayerUsesNativeVideoWithExistingControlsQualityAndCaptions() async throws {
        let web = try await nativeFixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          if (window.videojs || document.querySelector('video').controls) return false;
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          const quality = [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '清晰度 ›');
          if (!quality) return false;
          quality.click();
          const localQuality = document.querySelector('.video-player__menu-button.is-active')?.textContent;
          menu.click(); menu.click();
          const captions = [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '字幕 ›');
          if (!captions) return false;
          captions.click();
          const simplified = [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '简体中文');
          if (!simplified) return false;
          simplified.click();
          return localQuality === '1080p（本地缓存）' &&
            document.querySelector('video').textTracks[0].mode === 'showing';
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testPlaybackAndKeyboardDoNotDoubleDispatch() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          document.querySelector('.vjs-text-track-display').click();
          const played = mock.plays === 1 && !mock.paused && mock.overlayClicks === 0;
          document.querySelector('video').click();
          const paused = mock.paused;
          const button = document.querySelector('[data-action=toggle]');
          button.dispatchEvent(new KeyboardEvent('keydown', {key:' ', bubbles:true, cancelable:true}));
          const noUpstream = mock.upstreamKeys === 0;
          button.click();
          document.querySelector('[data-action=mute]').click();
          return played && paused && noUpstream && mock.plays === 2 && mock.muted &&
            document.querySelector('[data-icon=pause]').hidden === false;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testAppSpaceShortcutUsesThePlayerToggle() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          if (typeof window.yootubeTogglePlayback !== 'function') return false;
          window.yootubeTogglePlayback();
          const played = mock.plays === 1 && !mock.paused;
          window.yootubeTogglePlayback();
          return played && mock.paused;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testPlaybackEndIsForwardedToNativeDetail() async throws {
        let handler = PlayerSkinPlaybackHandler()
        let web = try await fixture(playbackHandler: handler)
        _ = try await web.evaluateJavaScript("fire('ended')")
        for _ in 0..<20 where !handler.stringMessages.contains("ended") {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(handler.stringMessages.contains("ended"))
    }

    func testPictureInPictureUsesNativeBridgeAndRestoresPlaybackState() async throws {
        let handler = PlayerSkinPlaybackHandler()
        let web = try await fixture(playbackHandler: handler)
        _ = try await web.evaluateJavaScript("""
        (() => {
          mock.time = 42; mock.volume = 0.4; mock.rate = 1.5;
          window.yootubeTogglePlayback();
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '画中画').click();
        })()
        """)
        for _ in 0..<20 where handler.dictionaryMessages.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }
        let message = try XCTUnwrap(handler.dictionaryMessages.first)
        let state = try XCTUnwrap(message["state"] as? [String: Any])
        XCTAssertEqual(message["action"] as? String, "pictureInPicture")
        XCTAssertEqual((state["currentTime"] as? NSNumber)?.doubleValue, 42)
        XCTAssertEqual((state["shouldPlay"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((state["volume"] as? NSNumber)?.doubleValue, 0.4)
        XCTAssertEqual((state["playbackRate"] as? NSNumber)?.doubleValue, 1.5)

        let result = try await web.evaluateJavaScript("""
        (() => {
          const pausedForHandoff = mock.paused;
          window.yootubeSetPictureInPictureState('active');
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          const showsExit = [...document.querySelectorAll('.video-player__menu-button')]
            .some(button => button.textContent === '退出画中画');
          menu.click();
          window.yootubeFinishPictureInPicture({state:{currentTime:58,shouldPlay:true,
            muted:true,volume:0.25,playbackRate:1.25},message:''});
          return [pausedForHandoff, showsExit, mock.time, mock.muted, mock.volume, mock.rate, mock.paused];
        })()
        """)
        let values = try XCTUnwrap(result as? [Any])
        XCTAssertEqual(values[0] as? Bool, true)
        XCTAssertEqual(values[1] as? Bool, true)
        XCTAssertEqual((values[2] as? NSNumber)?.doubleValue, 58)
        XCTAssertEqual(values[3] as? Bool, true)
        XCTAssertEqual((values[4] as? NSNumber)?.doubleValue, 0.25)
        XCTAssertEqual((values[5] as? NSNumber)?.doubleValue, 1.25)
        XCTAssertEqual(values[6] as? Bool, false)
    }

    func testAppSpaceShortcutLeavesTextAndModifiedKeysAlone() throws {
        func event(_ characters: String = " ", modifiers: NSEvent.ModifierFlags = [], repeat isRepeat: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isRepeat,
                keyCode: 49
            ))
        }

        XCTAssertTrue(PlaybackKeyboardShortcut.matches(try event(), firstResponder: nil))
        XCTAssertFalse(PlaybackKeyboardShortcut.matches(try event(), firstResponder: NSTextView()))
        XCTAssertFalse(PlaybackKeyboardShortcut.matches(try event(modifiers: .command), firstResponder: nil))
        XCTAssertFalse(PlaybackKeyboardShortcut.matches(try event(repeat: true), firstResponder: nil))
        XCTAssertFalse(PlaybackKeyboardShortcut.matches(try event("k"), firstResponder: nil))
    }

    func testAppKeyboardShortcutsRespectPageAndTextEditing() throws {
        func event(_ characters: String = "/", modifiers: NSEvent.ModifierFlags = [],
                   repeat isRepeat: Bool = false, keyCode: UInt16 = 44,
                   charactersIgnoringModifiers: String? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
                isARepeat: isRepeat,
                keyCode: keyCode
            ))
        }

        func action(_ event: NSEvent, responder: NSResponder? = nil,
                    video: Bool = false) -> AppKeyboardShortcutAction? {
            AppKeyboardShortcut.action(for: event, firstResponder: responder, hasVideoDetail: video)
        }

        XCTAssertEqual(action(try event()), .toggleSidebar)
        XCTAssertEqual(action(try event("h")), .home)
        XCTAssertEqual(action(try event("", keyCode: 123)), .back)
        XCTAssertEqual(action(try event("", keyCode: 124)), .forward)
        XCTAssertEqual(action(try event("k", modifiers: .command)), .focusSearch)
        XCTAssertEqual(action(try event("f", modifiers: .command)), .focusSearch)
        XCTAssertEqual(action(try event("n", modifiers: .command)), .newFavoriteFolder)
        XCTAssertEqual(action(try event(",", modifiers: .command)), .settings)
        XCTAssertEqual(action(try event("?", modifiers: .shift,
                                        charactersIgnoringModifiers: "/")), .keyboardShortcuts)
        XCTAssertEqual(action(try event("?")), .keyboardShortcuts)
        XCTAssertNil(action(try event("?", modifiers: .shift,
                                      charactersIgnoringModifiers: "/"), responder: NSTextView()))
        XCTAssertEqual(action(try event("1", modifiers: .command)), .home)
        for number in 2...8 {
            XCTAssertEqual(action(try event(String(number), modifiers: .command)),
                           .favoriteFolder(index: number - 2))
        }
        XCTAssertEqual(action(try event("9", modifiers: .command)), .lastFavoriteFolder)
        XCTAssertEqual(action(try event("b"), video: true), .saveVideo)
        XCTAssertEqual(action(try event("s"), video: true), .saveVideo)
        XCTAssertEqual(action(try event("f"), video: true), .theaterMode)
        XCTAssertEqual(action(try event("d"), video: true), .cacheVideo)
        XCTAssertEqual(action(try event("m"), video: true), .muteVideo)
        XCTAssertEqual(action(try event("c"), video: true), .captions)
        XCTAssertNil(action(try event("b")))
        XCTAssertNil(action(try event("h"), responder: NSTextView()))
        XCTAssertEqual(action(try event("k", modifiers: .command), responder: NSTextView()), .focusSearch)
        XCTAssertNil(action(try event("h", modifiers: .shift)))
        XCTAssertNil(action(try event(repeat: true)))
    }

    func testKeyboardShortcutsSheetListsEveryShortcutGroup() {
        let sections = KeyboardShortcutsSheet.sections
        XCTAssertEqual(sections.map(\.title), ["导航", "收藏夹", "视频播放"])
        XCTAssertTrue(sections[0].items.contains { $0.title == "设置" })
        XCTAssertEqual(sections[1].items.map(\.title),
                       ["首页", "第 1–7 个收藏夹", "最后一个收藏夹", "新建收藏夹"])
        XCTAssertTrue(sections[2].items.contains {
            $0.title == "影院模式 / 播放器全屏" && $0.keys == ["F"]
        })
        let keys = sections.flatMap(\.items).flatMap(\.keys)
        for expected in ["?", "/", "⌘ K", "⌘ F", "H", "←", "→", "⌘ 1", "⌘ 2 – ⌘ 8", "⌘ 9",
                         "⌘ N", "⌘ ,", "空格", "B", "S", "F", "D", "M", "C"] {
            XCTAssertTrue(keys.contains(expected), "快捷键弹窗缺少 \(expected)")
        }
    }

    func testSidebarShortcutHintLabelsMatchNumberShortcuts() {
        XCTAssertEqual(SidebarShortcutHints.homeLabel, "1")
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 0, folderCount: 1), ["2"])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 6, folderCount: 7), ["8"])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 6, folderCount: 8), ["8"])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 7, folderCount: 8), [])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 8, folderCount: 9), ["9"])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 7, folderCount: 10), [])
        XCTAssertEqual(SidebarShortcutHints.labels(forFolderAt: 9, folderCount: 10), ["9"])
    }

    func testToolbarSearchFieldLocatorFindsOnlyTheSearchField() throws {
        let root = NSView()
        let unrelated = NSTextField()
        unrelated.placeholderString = "其他输入框"
        let container = NSView()
        let search = NSTextField()
        search.placeholderString = ToolbarSearchFieldLocator.placeholder
        root.addSubview(unrelated)
        root.addSubview(container)
        container.addSubview(search)

        XCTAssertTrue(try XCTUnwrap(ToolbarSearchFieldLocator.find(in: root)) === search)
        XCTAssertNil(ToolbarSearchFieldLocator.find(in: unrelated))
    }

    func testToolbarSearchFieldResignsOnlyForClicksOutsideIt() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let root = try XCTUnwrap(window.contentView)
        let search = NSTextField(frame: NSRect(x: 100, y: 220, width: 260, height: 36))
        search.placeholderString = ToolbarSearchFieldLocator.placeholder
        root.addSubview(search)
        search.selectText(nil)

        XCTAssertFalse(ToolbarSearchFieldLocator.shouldResignSearch(
            forClickAt: NSPoint(x: 230, y: 238), in: window))
        XCTAssertTrue(ToolbarSearchFieldLocator.shouldResignSearch(
            forClickAt: NSPoint(x: 40, y: 120), in: window))
    }

    func testNativeVideoShortcutFunctionsUseTheExistingPlayerActions() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          if (typeof window.yootubeToggleTheaterMode !== 'function' ||
              typeof window.yootubeToggleMute !== 'function' ||
              typeof window.yootubeToggleCaptions !== 'function') return false;
          window.yootubeToggleTheaterMode();
          const theater = document.querySelector('[data-action=theater]').getAttribute('aria-pressed') === 'true';
          window.yootubeToggleMute();
          const muted = mock.muted;
          window.yootubeToggleCaptions();
          const captions = textTrackList[0].mode === 'showing';
          return theater && muted && captions;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testFKeyDelegatesThePresentationCycleToTheNativeApp() async throws {
        let handler = PlayerSkinPlaybackHandler()
        let web = try await fixture(playbackHandler: handler)
        _ = try await web.evaluateJavaScript("""
        window.dispatchEvent(new KeyboardEvent('keydown', {key:'f', bubbles:true, cancelable:true}))
        """)
        for _ in 0..<20 where !handler.stringMessages.contains("displayCycle") {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertTrue(handler.stringMessages.contains("displayCycle"))
        XCTAssertFalse(handler.stringMessages.contains("theater"))
    }

    func testEscapeLeavesPlayerFullScreenBeforeLeavingTheaterMode() async throws {
        let handler = PlayerSkinPlaybackHandler()
        let web = try await fixture(playbackHandler: handler)
        let result = try await web.evaluateJavaScript("""
        (() => {
          window.yootubeSetTheaterMode(true);
          window.yootubeSetPlayerFullScreen?.(true);
          window.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true, cancelable:true}));
          return document.querySelector('[data-action=theater]').getAttribute('aria-pressed');
        })()
        """)
        for _ in 0..<20 where !handler.stringMessages.contains("exitPlayerFullScreen") {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(result as? String, "true")
        XCTAssertTrue(handler.stringMessages.contains("exitPlayerFullScreen"))
        XCTAssertFalse(handler.stringMessages.contains("standard"))
    }

    func testPointerGestureDoesNotUndoNativeMediaToggle() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const video = document.querySelector('video');
          video.addEventListener('mouseup', () => { mock.paused = !mock.paused; });
          const clickSurface = () => {
            video.dispatchEvent(new PointerEvent('pointerdown', {button:0, pointerId:1, bubbles:true, cancelable:true}));
            video.dispatchEvent(new MouseEvent('mousedown', {button:0, bubbles:true, cancelable:true}));
            video.dispatchEvent(new MouseEvent('mouseup', {button:0, bubbles:true, cancelable:true}));
            video.dispatchEvent(new MouseEvent('click', {button:0, bubbles:true, cancelable:true}));
          };
          mock.paused = false;
          clickSurface();
          const paused = mock.paused;
          clickSurface();
          return paused && !mock.paused;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testTimelineHoverKeyboardBoundsAndUnknownDuration() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const t = document.querySelector('.video-player__timeline');
          const key = k => t.dispatchEvent(new KeyboardEvent('keydown', {key:k,bubbles:true,cancelable:true}));
          const rect = t.getBoundingClientRect();
          t.dispatchEvent(new PointerEvent('pointerenter', {clientX:rect.left + rect.width/2}));
          const preview = document.querySelector('.video-player__timeline-tooltip').textContent === '1:00';
          mock.time = 118; key('ArrowRight');
          const upper = mock.time === 120;
          key('Home'); key('ArrowLeft'); const lower = mock.time === 0;
          key('ArrowRight'); const once = mock.time === 5 && mock.upstreamKeys === 0;
          key('End'); const end = mock.time === 120;
          mock.duration = Infinity; key('Home');
          return preview && upper && lower && once && end && mock.time === 120;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testSettingsUseDirectEngineChoices() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const button = document.querySelector('[data-action=menu]'); button.click();
          document.querySelector('[data-speed="1.5"]').click();
          const speed = mock.rate === 1.5 && document.querySelector('[data-speed="1.5"]').getAttribute('aria-pressed') === 'true';
          button.click();
          button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '清晰度 ›').click();
          const choice = [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '720p');
          choice.click();
          const quality = qualityLevels.every(level => level.enabled === (level.height === 720)) &&
            button.getAttribute('aria-expanded') === 'false';
          button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '字幕 ›').click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === 'Chinese (Traditional)').click();
          const captions = textTrackList[0].mode === 'disabled' && textTrackList[1].mode === 'showing';
          button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '音轨 ›').click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === 'Original').click();
          const audio = !audioTrackList[0].enabled && audioTrackList[1].enabled;
          return [speed, quality, captions, audio];
        })()
        """)
        XCTAssertEqual(result as? [Bool], [true, true, true, true])
    }

    func testQualitySelectionSwitchesDirectlyToTargetLevel() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const button = document.querySelector('[data-action=menu]'); button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '清晰度 ›').click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '144p').click();
          return mock.qualitySwitches;
        })()
        """)
        XCTAssertEqual(result as? [Int], [144])
    }

    func testQualitySelectionRunsBeforeAnUpstreamClickInterceptor() async throws {
        let web = try await fixture(blocksMenuClicks: true)
        let result = try await web.evaluateJavaScript("""
        (() => {
          const pointerClick = button => {
            button.dispatchEvent(new PointerEvent('pointerdown', {button:0, pointerId:1, bubbles:true, cancelable:true}));
            const video = document.querySelector('video');
            video.dispatchEvent(new PointerEvent('pointerup', {button:0, pointerId:1, bubbles:true, cancelable:true}));
            video.dispatchEvent(new MouseEvent('click', {button:0, bubbles:true, cancelable:true}));
          };
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '清晰度 ›'));
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '1080p'));
          menu.click();
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '清晰度 ›'));
          const activeQuality = [...document.querySelectorAll('.video-player__menu-button.is-active')]
            .map(button => button.textContent);
          menu.click();
          menu.click();
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '字幕 ›'));
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === 'Chinese (Simplified)'));
          menu.click();
          pointerClick([...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '字幕 ›'));
          const activeCaption = [...document.querySelectorAll('.video-player__menu-button.is-active')]
            .map(button => button.textContent);
          return mock.qualitySwitches.join(',') === '1080' &&
            activeQuality.length === 1 && activeQuality[0] === '1080p' &&
            textTrackList[0].mode === 'showing' && textTrackList[1].mode === 'disabled' &&
            activeCaption.length === 1 && activeCaption[0] === 'Chinese (Simplified)' &&
            mock.plays === 0;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testQualitySelectionSurvivesQualityLevelRebuild() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("""
        (() => {
          const button = document.querySelector('[data-action=menu]'); button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '清晰度 ›').click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '960p').click();
          rebuildQualityLevels();
        })()
        """)
        try await Task.sleep(for: .milliseconds(50))
        let result = try await web.evaluateJavaScript("""
        (() => {
          const fixed = qualityLevels.every(level => level.enabled === (level.height === 960));
          const button = document.querySelector('[data-action=menu]'); button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '清晰度 ›').click();
          const active = [...document.querySelectorAll('.video-player__menu-button.is-active')].map(b => b.textContent);
          return fixed && active.length === 1 && active[0] === '960p';
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testStoredQualityAppliesBeforePlaybackWithoutASecondSwitch() async throws {
        let web = try await fixture(storedQuality: 1080)
        let before = try await web.evaluateJavaScript("""
        (() => {
          const active = qualityLevels.filter(level => level.enabled).map(level => level.height);
          const button = document.querySelector('[data-action=menu]'); button.click();
          [...document.querySelectorAll('.video-player__menu-button')].find(b => b.textContent === '清晰度 ›').click();
          return [active.join(','), mock.qualitySwitches.join(','),
            document.querySelector('.video-player__menu-button.is-active')?.textContent || ''];
        })()
        """)
        XCTAssertEqual(before as? [String], ["1080", "1080", "1080p"])

        _ = try await web.evaluateJavaScript("fire('playing')")
        try await Task.sleep(for: .milliseconds(650))
        let after = try await web.evaluateJavaScript("mock.qualitySwitches.join(',')")
        XCTAssertEqual(after as? String, "1080")
    }

    func testCaptionsButtonAndTheaterModeState() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const actions = [...document.querySelectorAll('.video-player__toolbar-button')].map(b => b.dataset.action);
          const cc = document.querySelector('[data-action=captions]');
          cc.click();
          const captionsOn = textTrackList[0].mode === 'showing' && cc.getAttribute('aria-pressed') === 'true';
          cc.click();
          const captionsOff = textTrackList.every(track => track.mode === 'disabled') && cc.getAttribute('aria-pressed') === 'false';
          const theater = document.querySelector('[data-action=theater]'); theater.click();
          const theaterOn = !document.querySelector('[data-icon=theater-exit]').hidden && theater.getAttribute('aria-pressed') === 'true';
          const menu = document.querySelector('[data-action=menu]'); menu.click();
          window.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape',cancelable:true}));
          const onlyMenuClosed = document.querySelector('.video-player__menu').hidden && !document.querySelector('[data-icon=theater-exit]').hidden;
          window.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape',cancelable:true}));
          return actions.join(',') === 'mute,captions,theater,menu' && captionsOn && captionsOff &&
                 theaterOn && onlyMenuClosed && document.querySelector('[data-icon=theater-exit]').hidden;
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testSelectedCaptionIsReappliedAfterTheTrackListChanges() async throws {
        let web = try await fixture()
        _ = try await web.evaluateJavaScript("""
        (() => {
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '字幕 ›').click();
          [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === 'Chinese (Traditional)').click();
          textTrackList.splice(0, textTrackList.length,
            {kind:'captions',label:'Chinese (Simplified)',language:'zh-Hans',mode:'showing'},
            {kind:'captions',label:'Chinese (Traditional)',language:'zh-Hant',mode:'disabled'});
          textTrackList.emit('addtrack');
        })()
        """)
        try await Task.sleep(for: .milliseconds(50))
        let result = try await web.evaluateJavaScript("""
        (() => {
          const menu = document.querySelector('[data-action=menu]');
          menu.click();
          [...document.querySelectorAll('.video-player__menu-button')]
            .find(button => button.textContent === '字幕 ›').click();
          const active = [...document.querySelectorAll('.video-player__menu-button.is-active')]
            .map(button => button.textContent);
          return textTrackList[0].mode === 'disabled' && textTrackList[1].mode === 'showing' &&
            active.length === 1 && active[0] === 'Chinese (Traditional)';
        })()
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testReferenceButtonsOverrideEngineResetAndFitNarrowPlayer() async throws {
        let web = try await fixture()
        web.frame.size = CGSize(width: 375, height: 211)
        let result = try await web.evaluateJavaScript("""
        (() => {
          const button = document.querySelector('[data-action=toggle]');
          const css = getComputedStyle(button);
          const more = document.querySelector('[data-action=menu]').getBoundingClientRect();
          const progress = document.querySelector('.video-player__timeline').getBoundingClientRect();
          return [css.backgroundColor, css.display, css.borderRadius, String(progress.width > 30), String(more.right <= innerWidth)];
        })()
        """)
        // Grid items blockify inline-flex to flex in computed styles.
        XCTAssertEqual(result as? [String], ["rgba(255, 255, 255, 0.1)", "flex", "999px", "true", "true"])
    }

    func testVideoFitReportsRealAspectWithoutAddingAPlayerUnderlay() async throws {
        let handler = PlayerSkinPlaybackHandler()
        let web = try await fixture(playbackHandler: handler)
        let result = try await web.evaluateJavaScript("""
        (() => {
          const shell = document.querySelector('#player');
          document.querySelector('.vjs-tech').classList.remove('vjs-tech');
          const video = document.createElement('div');
          video.className = 'vjs-tech';
          shell.appendChild(video);
          const dimensions = (width, height) => {
            video.videoWidth = width;
            video.videoHeight = height;
            window.dispatchEvent(new Event('resize'));
            const style = getComputedStyle(video);
            return [style.objectFit, style.backgroundColor];
          };
          return dimensions(1920, 960);
        })()
        """)
        XCTAssertEqual(result as? [String], ["contain", "rgba(0, 0, 0, 0)"])
        for _ in 0..<20 where !handler.dictionaryMessages.contains(where: {
            $0["action"] as? String == "aspectRatio"
        }) {
            try await Task.sleep(for: .milliseconds(25))
        }
        let message = try XCTUnwrap(handler.dictionaryMessages.last(where: {
            $0["action"] as? String == "aspectRatio"
        }))
        XCTAssertEqual(try XCTUnwrap(message["value"] as? NSNumber).doubleValue,
                       2, accuracy: 0.0001)
    }

    func testVideoFitReevaluatesWhenPlaybackStartsAfterDimensionsBecomeAvailable() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const shell = document.querySelector('#player');
          document.querySelector('.vjs-tech').classList.remove('vjs-tech');
          const video = document.createElement('div');
          video.className = 'vjs-tech';
          video.videoWidth = 0;
          video.videoHeight = 0;
          shell.appendChild(video);
          window.dispatchEvent(new Event('resize'));
          const before = getComputedStyle(video).objectFit;
          video.videoWidth = 1920;
          video.videoHeight = 1080;
          fire('playing');
          return [before, getComputedStyle(video).objectFit];
        })()
        """)
        XCTAssertEqual(result as? [String], ["contain", "contain"])
    }

    func testPlayerUnderlayBecomesTransparentOnceVideoIsPresent() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          const colors = () => [
            getComputedStyle(document.documentElement).backgroundColor,
            getComputedStyle(document.body).backgroundColor,
            getComputedStyle(document.querySelector('#player')).backgroundColor,
            getComputedStyle(document.querySelector('.vjs-tech')).backgroundColor
          ];
          const loading = colors();
          fire('playing');
          return [loading, colors()];
        })()
        """)
        XCTAssertEqual(result as? [[String]], [
            ["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)",
             "rgb(0, 0, 0)", "rgba(0, 0, 0, 0)"],
            ["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)",
             "rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)"]
        ])
    }

    func testPlayerFullScreenUsesBlackUnderlayOnlyWhileActive() async throws {
        let web = try await fixture()
        let result = try await web.evaluateJavaScript("""
        (() => {
          fire('playing');
          const colors = () => [
            getComputedStyle(document.documentElement).backgroundColor,
            getComputedStyle(document.body).backgroundColor,
            getComputedStyle(document.querySelector('#player')).backgroundColor
          ];
          const standard = colors();
          window.yootubeSetPlayerFullScreen(true);
          const fullScreen = colors();
          window.yootubeSetPlayerFullScreen(false);
          return [standard, fullScreen, colors()];
        })()
        """)
        XCTAssertEqual(result as? [[String]], [
            ["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)"],
            ["rgb(0, 0, 0)", "rgb(0, 0, 0)", "rgb(0, 0, 0)"],
            ["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)"]
        ])
    }

    private static let html = #"""
    <!doctype html><html><head><style>
    #player {position:absolute; width:720px; height:405px;} video {width:100%;height:100%;}
    .video-js button {background:none; display:inline-block; border:0; color:inherit; padding:0;}
    </style></head><body><div id="player" class="video-js" tabindex="0"><video class="vjs-tech"></video>
    <div class="vjs-text-track-display"></div>
    <div class="vjs-control-bar"><div class="vjs-quality-selector"><button class="vjs-menu-item" onclick="mock.qualityClicks++">720p</button></div></div>
    </div><script>
    /* QUALITY_PREFERENCE */
    /* MENU_CLICK_INTERCEPTOR */
    window.mock = {time:30,duration:120,paused:true,rate:1,volume:1,muted:false,plays:0,upstreamKeys:0,qualityClicks:0,qualitySwitches:[],overlayClicks:0};
    const handlers = {};
    const field = key => function(value) {if(value !== undefined) mock[key] = value; return mock[key];};
    const fire = event => (handlers[event] || []).forEach(fn => fn());
    const observedList = items => {
      const listeners = {};
      return Object.assign(items, {
        on:(event, fn) => (listeners[event] ||= []).push(fn),
        emit:event => (listeners[event] || []).forEach(fn => fn())
      });
    };
    window.textTrackList = observedList([
      {kind:'captions',label:'Chinese (Simplified)',language:'zh-Hans',mode:'disabled'},
      {kind:'captions',label:'Chinese (Traditional)',language:'zh-Hant',mode:'disabled'}
    ]);
    window.audioTrackList = observedList([
      {label:'Dubbed',language:'zh',enabled:true},
      {label:'Original',language:'en',enabled:false}
    ]);
    let selectedQualityIndex = 1;
    const qualityLevel = (height, index) => {
      let enabled = true;
      return {height,
        get enabled() { return enabled; },
        set enabled(value) {
          value = !!value;
          if (enabled === value) return;
          enabled = value;
        }
      };
    };
    const qualityHeights = [360, 720, 1080, 960, 144];
    window.qualityLevels = observedList(qualityHeights.map(qualityLevel));
    Object.defineProperty(qualityLevels, 'selectedIndex', {get: () => selectedQualityIndex});
    const qualityController = {
      fastQualityChange_:() => {
        const index = qualityLevels.findIndex(level => level.enabled);
        if (index < 0) return;
        selectedQualityIndex = index;
        mock.qualitySwitches.push(qualityLevels[index].height);
        qualityLevels.emit('change');
      }
    };
    window.rebuildQualityLevels = () => {
      qualityLevels.splice(0);
      selectedQualityIndex = -1;
      fire('loadstart');
      qualityHeights.forEach((height, index) => {
        qualityLevels.push(qualityLevel(height, index));
        if (selectedQualityIndex < 0) selectedQualityIndex = 0;
        qualityLevels.emit('addqualitylevel');
      });
      fire('loadedmetadata');
    };
    const engine = {
      el:() => document.getElementById('player'), ready:fn => fn(),
      duration:field('duration'),currentTime:field('time'),paused:field('paused'),ended:() => false,
      muted:field('muted'),volume:field('volume'),playbackRate:field('rate'),
      textTracks:() => textTrackList,audioTracks:() => audioTrackList,qualityLevels:() => qualityLevels,
      tech:() => ({vhs:{masterPlaylistController_:qualityController}}),
      play:() => {mock.paused=false;mock.plays++;fire('play');return Promise.resolve();},
      pause:() => {mock.paused=true;fire('pause');},
      on:(names,fn) => (Array.isArray(names)?names:[names]).forEach(name => (handlers[name] ||= []).push(fn))
    };
    window.videojs = {getPlayer:() => engine};
    // Video.js owns the player shell and may consume trusted clicks before a
    // custom menu button's target listener runs.
    document.getElementById('player').addEventListener('click', event => {
      if (event.target.closest?.('.video-player__menu')) event.stopImmediatePropagation();
    }, true);
    // Simulate the upstream global shortcut and media click handlers to catch double actions.
    window.addEventListener('keydown', () => {mock.upstreamKeys++;});
    document.querySelector('video').addEventListener('click', () => {mock.plays++;});
    document.querySelector('.vjs-text-track-display').addEventListener('click', () => {mock.overlayClicks++;});
    </script></body></html>
    """#

    private static let nativeHTML = #"""
    <!doctype html><html><head><style>
    #player {position:absolute; width:720px; height:405px;} video {width:100%;height:100%;}
    </style></head><body><div id="player" class="video-js"><video class="vjs-tech"
      data-quality="1080p（本地缓存）"><track kind="subtitles" label="简体中文"
      srclang="zh-Hans" src="data:text/vtt,WEBVTT%0A%0A00%3A00.000%20--%3E%2000%3A01.000%0A%E6%B5%8B%E8%AF%95"></video>
      <div class="vjs-text-track-display"></div></div></body></html>
    """#
}

@MainActor
private final class PlayerSkinPlaybackHandler: NSObject, WKScriptMessageHandler {
    private(set) var dictionaryMessages: [[String: Any]] = []
    private(set) var stringMessages: [String] = []

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if let values = message.body as? [String: Any] {
            dictionaryMessages.append(values)
        } else if let value = message.body as? String {
            stringMessages.append(value)
        }
    }
}
