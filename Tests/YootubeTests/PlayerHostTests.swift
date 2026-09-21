import SwiftUI
import WebKit
import XCTest
@testable import Yootube

@MainActor
final class PlayerHostTests: XCTestCase {
    func testLoadingChangesReachTheNativeSurfaceThroughSwiftUI() async throws {
        let state = SurfaceState()
        let root = NSHostingView(rootView: SurfaceFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 720, height: 405),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.orderBack(nil)
        defer { window.close() }

        try await waitUntil { self.findPlayer(in: root) != nil }
        let player = try XCTUnwrap(findPlayer(in: root))
        let overlay = try XCTUnwrap(player.subviews.last)
        XCTAssertFalse(overlay.isHidden)

        state.loading = false
        try await waitUntil { overlay.isHidden }
        state.error = "Connection failed"
        try await waitUntil { !overlay.isHidden }
        state.retry()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(overlay.isHidden)
        state.loading = false
        try await waitUntil { overlay.isHidden }

        XCTAssertTrue(findPlayer(in: root) === player)
        XCTAssertTrue(player.webView === state.webView)
    }

    private func findPlayer(in view: NSView) -> PlayerHostView? {
        if let player = view as? PlayerHostView { return player }
        return view.subviews.lazy.compactMap { self.findPlayer(in: $0) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<50 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "SwiftUI did not update the native player surface")
    }

    func testLoadingPlaybackErrorAndResizeUseOneClipWithWebContentPastItsEdge() throws {
        let web = WKWebView()
        let host = PlayerHostView(webView: web)
        let status = try XCTUnwrap(host.subviews.last)
        XCTAssertTrue(status !== web)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(host.layer?.cornerRadius, 12)
        XCTAssertEqual(host.layer?.masksToBounds, true)

        for size in [CGSize(width: 720, height: 405), CGSize(width: 641.5, height: 360.84375),
                     CGSize(width: 1280, height: 720), CGSize(width: 720, height: 405)] {
            host.frame.size = size
            host.layout()
            XCTAssertTrue(web.superview === host)
            XCTAssertEqual(web.frame, host.bounds.insetBy(
                dx: -PlayerHostView.webContentBleed,
                dy: -PlayerHostView.webContentBleed
            ))
            XCTAssertEqual(status.frame, host.bounds)
            host.updateStatus(loading: false, error: nil, retry: {})
            XCTAssertTrue(status.isHidden)
            host.updateStatus(loading: false, error: "Connection failed", retry: {})
            XCTAssertFalse(status.isHidden)
            host.updateStatus(loading: true, error: nil, retry: {})
            XCTAssertFalse(status.isHidden)
        }
    }

    func testRestoresWebViewFrameAfterLeavingPlayerFullScreen() {
        let web = WKWebView()
        let host = PlayerHostView(webView: web)
        host.frame.size = CGSize(width: 720, height: 405)
        host.layout()
        web.frame = NSRect(x: 0, y: 160, width: 720, height: 405)

        host.restoreWebViewLayoutAfterFullScreen()

        XCTAssertEqual(web.frame, host.bounds.insetBy(
            dx: -PlayerHostView.webContentBleed,
            dy: -PlayerHostView.webContentBleed
        ))
    }
}

@MainActor
private final class SurfaceState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    let webView = WKWebView()

    func retry() {
        error = nil
        loading = true
    }
}

private struct SurfaceFixture: View {
    @ObservedObject var state: SurfaceState

    var body: some View {
        EmbeddedPlayer(webView: state.webView, loading: state.loading,
                       error: state.error, retry: state.retry)
    }
}
