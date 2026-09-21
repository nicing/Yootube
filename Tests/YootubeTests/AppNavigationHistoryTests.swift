import XCTest
@testable import Yootube

final class AppNavigationHistoryTests: XCTestCase {
    private let search = AppDestination.page(URL(string: "http://127.0.0.1:38473/search?q=swift")!)
    private let channel = AppDestination.page(URL(string: "http://127.0.0.1:38473/channel/UCtest")!)
    private let video = AppDestination.page(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!)

    func testRecordsEveryPageAcrossMultipleBackAndForwardSteps() {
        var history = AppNavigationHistory()
        history.visit(search)
        history.visit(channel)
        history.visit(video)

        XCTAssertEqual(history.goBack(), channel)
        XCTAssertEqual(history.goBack(), search)
        XCTAssertEqual(history.goBack(), .home)
        XCTAssertNil(history.goBack())
        XCTAssertEqual(history.goForward(), search)
        XCTAssertEqual(history.goForward(), channel)
        XCTAssertEqual(history.goForward(), video)
        XCTAssertNil(history.goForward())
    }

    func testFolderAndVideoShareTheSameHistory() {
        let folderID = UUID()
        var history = AppNavigationHistory()
        history.visit(.folder(folderID))
        history.visit(video)

        XCTAssertEqual(history.goBack(), .folder(folderID))
        XCTAssertEqual(history.goForward(), video)
    }

    func testVisitingAfterBackClearsTheOldForwardBranch() {
        var history = AppNavigationHistory()
        history.visit(search)
        history.visit(channel)
        XCTAssertEqual(history.goBack(), search)

        history.visit(video)

        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.entries, [.home, search, video])
    }

    func testConsecutiveDuplicateDoesNotCreateAnotherEntry() {
        var history = AppNavigationHistory()
        history.visit(search)
        history.visit(search)

        XCTAssertEqual(history.entries, [.home, search])
    }

    func testWebViewTraversalCanReconcileWithExistingHistory() {
        let folderID = UUID()
        var history = AppNavigationHistory()
        history.visit(search)
        history.visit(.folder(folderID))
        history.visit(channel)

        XCTAssertTrue(history.moveBackward(to: search))
        XCTAssertEqual(history.current, search)
        XCTAssertTrue(history.moveForward(to: channel))
        XCTAssertEqual(history.current, channel)
    }

    func testRedirectReplacesRequestedURLWithoutAddingAnotherPage() {
        let handle = AppDestination.page(URL(string: "http://127.0.0.1:38473/@apple")!)
        var history = AppNavigationHistory()
        history.visit(search)
        history.visit(handle)

        XCTAssertTrue(history.replaceCurrent(from: handle, with: channel))
        XCTAssertEqual(history.entries, [.home, search, channel])
        XCTAssertEqual(history.goBack(), search)
        XCTAssertEqual(history.goForward(), channel)
    }

    func testToolbarReplayUsesTheExistingWebViewHistoryDirection() {
        let searchURL = URL(string: "http://127.0.0.1:38473/search?q=swift")!
        let channelURL = URL(string: "http://127.0.0.1:38473/channel/UCtest")!
        let videoURL = URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!

        XCTAssertEqual(
            BrowserHistoryReplayAction.resolve(
                target: channelURL,
                current: videoURL,
                back: channelURL,
                forward: nil,
                direction: .backward
            ),
            .goBack
        )
        XCTAssertEqual(
            BrowserHistoryReplayAction.resolve(
                target: videoURL,
                current: channelURL,
                back: searchURL,
                forward: videoURL,
                direction: .forward
            ),
            .goForward
        )
    }

    func testToolbarReplayChoosesTheRequestedDirectionForDuplicateURLs() {
        let repeatedURL = URL(string: "http://127.0.0.1:38473/search?q=swift")!
        let currentURL = URL(string: "http://127.0.0.1:38473/channel/UCtest")!

        XCTAssertEqual(
            BrowserHistoryReplayAction.resolve(
                target: repeatedURL,
                current: currentURL,
                back: repeatedURL,
                forward: repeatedURL,
                direction: .backward
            ),
            .goBack
        )
        XCTAssertEqual(
            BrowserHistoryReplayAction.resolve(
                target: repeatedURL,
                current: currentURL,
                back: repeatedURL,
                forward: repeatedURL,
                direction: .forward
            ),
            .goForward
        )
    }
}
