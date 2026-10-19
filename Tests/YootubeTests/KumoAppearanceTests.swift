import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Yootube

@MainActor
final class KumoAppearanceTests: XCTestCase {
    func testNativeThemeUsesAppleNeutralPaletteInBothAppearances() {
        let light: [(Color, UInt32, CGFloat)] = [
            (KumoTheme.sidebar, 0xF5F5F5, 1),
            (KumoTheme.canvas, 0xFFFFFF, 1),
            (KumoTheme.base, 0xFAFAFC, 1),
            (KumoTheme.recessed, 0xF5F5F7, 1),
            (KumoTheme.tint, 0xD2D2D7, 0.64),
            (KumoTheme.line, 0xE0E0E0, 1),
            (KumoTheme.text, 0x1D1D1F, 1),
            (KumoTheme.subtle, 0x7A7A7A, 1),
            (KumoTheme.focus, 0x1D1D1F, 1),
            (KumoTheme.placeholder, 0xF5F5F7, 1),
            (KumoTheme.skeleton, 0xF0F0F0, 1),
            (KumoTheme.skeletonHighlight, 0xFAFAFC, 1),
            (KumoTheme.selectedShortcut, 0xD2D2D7, 1)
        ]
        let dark: [(Color, UInt32, CGFloat)] = [
            (KumoTheme.sidebar, 0x1E1E1E, 1),
            (KumoTheme.canvas, 0x2A2A2C, 1),
            (KumoTheme.base, 0x2A2A2C, 1),
            (KumoTheme.recessed, 0x272729, 1),
            (KumoTheme.tint, 0x333333, 1),
            (KumoTheme.line, 0x333333, 1),
            (KumoTheme.text, 0xFFFFFF, 1),
            (KumoTheme.subtle, 0xCCCCCC, 1),
            (KumoTheme.focus, 0xFFFFFF, 1),
            (KumoTheme.placeholder, 0x272729, 1),
            (KumoTheme.skeleton, 0x272729, 1),
            (KumoTheme.skeletonHighlight, 0x2A2A2C, 1),
            (KumoTheme.selectedShortcut, 0x252527, 1)
        ]

        light.forEach { assertColor($0.0, appearance: .aqua, hex: $0.1, alpha: $0.2) }
        dark.forEach { assertColor($0.0, appearance: .darkAqua, hex: $0.1, alpha: $0.2) }
        assertColor(KumoTheme.ink, appearance: .aqua, hex: 0x1D1D1F, alpha: 1)
        assertColor(KumoTheme.bodyOnDark, appearance: .aqua, hex: 0xFFFFFF, alpha: 1)
        assertColor(KumoTheme.surfaceBlack, appearance: .aqua, hex: 0x000000, alpha: 1)
        assertColor(Color(nsColor: KumoTheme.windowColor(dark: false)),
                    appearance: .aqua, hex: 0xF5F5F5, alpha: 1)
        assertColor(Color(nsColor: KumoTheme.windowColor(dark: true)),
                    appearance: .darkAqua, hex: 0x1E1E1E, alpha: 1)
    }

    func testThemeUpdatesPreserveWindowChromeAndGeometry() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.toolbar = NSToolbar(identifier: "KumoAppearanceTests")
        let chrome = StandardWindowChrome.ChromeView()
        let originalTitlebarViews = window.standardWindowButton(.closeButton)?.superview?.subviews ?? []
        window.contentView?.addSubview(chrome)
        let original = window.frame
        for dark in [false, true, false] {
            chrome.dark = dark
            chrome.applyStyle()
            XCTAssertEqual(window.backgroundColor, KumoTheme.windowColor(dark: dark))
            XCTAssertEqual(window.frame, original)
            XCTAssertFalse(window.titlebarAppearsTransparent)
            XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
            XCTAssertEqual(window.titlebarSeparatorStyle, .none)
            XCTAssertEqual(window.toolbar?.showsBaselineSeparator, false)
            XCTAssertEqual(window.standardWindowButton(.closeButton)?.superview?.subviews, originalTitlebarViews)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                XCTAssertEqual(window.standardWindowButton(type)?.isHidden, false)
                XCTAssertEqual(window.standardWindowButton(type)?.isEnabled, true)
            }
        }
    }

    func testWebAppearanceUpdatesWithoutNavigation() async throws {
        let web = try await makeWeb(path: "/search")
        let original = web.url
        let appearances: [(NSAppearance.Name, [String])] = [
            (.aqua, ["rgb(255, 255, 255)", "rgb(29, 29, 31)",
                     "rgb(250, 250, 252)", "rgb(224, 224, 224)"]),
            (.darkAqua, ["rgb(42, 42, 44)", "rgb(255, 255, 255)",
                         "rgb(42, 42, 44)", "rgb(51, 51, 51)"]),
            (.aqua, ["rgb(255, 255, 255)", "rgb(29, 29, 31)",
                     "rgb(250, 250, 252)", "rgb(224, 224, 224)"])
        ]
        for (appearance, expected) in appearances {
            web.appearance = NSAppearance(named: appearance)
            var actual: [String]?
            for _ in 0..<40 {
                actual = try await web.evaluateJavaScript("""
                (() => {
                  const body = getComputedStyle(document.body);
                  const input = getComputedStyle(document.querySelector('input'));
                  return [body.backgroundColor, body.color, input.backgroundColor, input.borderTopColor];
                })()
                """) as? [String]
                if actual == expected { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(web.url, original)
            let value = try await web.evaluateJavaScript("document.querySelector('input').value") as? String
            XCTAssertEqual(value, "preserve query")
        }
    }

    func testWebSkinDoesNotEnterPlayerDocuments() async throws {
        let web = try await makeWeb(path: "/embed/sZSlTDlo0Ag")
        let result = try await web.evaluateJavaScript("document.getElementById('yootube-kumo-theme') === null")
        XCTAssertEqual(result as? Bool, true)
    }

    private func makeWeb(path: String) async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: KumoWebTheme.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 760, height: 520), configuration: config)
        web.loadHTMLString("<html><head></head><body><form class='pure-form'><input value='preserve query'></form></body></html>",
                           baseURL: URL(string: "http://127.0.0.1:38473\(path)"))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("document.readyState")) as? String == "complete", !web.isLoading { return web }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("WebKit did not finish loading the appearance fixture")
        return web
    }

    private func assertColor(_ color: Color, appearance: NSAppearance.Name,
                             hex: UInt32, alpha expectedAlpha: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let appearance = NSAppearance(named: appearance) else {
            return XCTFail("Missing appearance", file: file, line: line)
        }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        guard let resolved else { return XCTFail("Unable to resolve color", file: file, line: line) }
        XCTAssertEqual(resolved.redComponent, CGFloat((hex >> 16) & 0xFF) / 255,
                       accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255,
                       accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, CGFloat(hex & 0xFF) / 255,
                       accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, expectedAlpha,
                       accuracy: 0.01, file: file, line: line)
    }
}
