import AppKit
import XCTest
@testable import Yootube

final class WindowStyleTests: XCTestCase {
    @MainActor
    func testRestoresNativeTitleBarAndSystemButtons() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.toolbar = NSToolbar(identifier: "WindowStyleTests")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        StandardWindowChrome.apply(to: window)
        XCTAssertTrue(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertEqual(window.toolbar?.showsBaselineSeparator, false)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let control = try XCTUnwrap(window.standardWindowButton(button))
            XCTAssertFalse(control.isHidden)
            XCTAssertTrue(control.isEnabled)
        }
    }

    @MainActor
    func testRepeatedContentUpdatesKeepWindowGeometryAndStyle() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        StandardWindowChrome.apply(to: window)
        let frame = window.frame
        let style = window.styleMask
        for _ in 0..<10 { StandardWindowChrome.apply(to: window) }
        XCTAssertEqual(window.styleMask, style)
        XCTAssertEqual(window.frame, frame)
        XCTAssertFalse(window.titlebarAppearsTransparent)
    }
}
