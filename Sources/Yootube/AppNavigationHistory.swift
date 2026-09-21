import Foundation

enum AppDestination: Equatable {
    case home
    case folder(UUID)
    case page(URL)
}

struct AppNavigationHistory {
    private(set) var entries: [AppDestination]
    private(set) var index: Int

    init(initial: AppDestination = .home) {
        entries = [initial]
        index = 0
    }

    var current: AppDestination { entries[index] }
    var canGoBack: Bool { index > entries.startIndex }
    var canGoForward: Bool { index < entries.index(before: entries.endIndex) }

    mutating func visit(_ destination: AppDestination) {
        guard destination != current else { return }
        if canGoForward {
            entries.removeSubrange(entries.index(after: index)..<entries.endIndex)
        }
        entries.append(destination)
        index = entries.index(before: entries.endIndex)
    }

    mutating func goBack() -> AppDestination? {
        guard canGoBack else { return nil }
        index = entries.index(before: index)
        return current
    }

    mutating func goForward() -> AppDestination? {
        guard canGoForward else { return nil }
        index = entries.index(after: index)
        return current
    }

    mutating func replaceCurrent(from source: AppDestination, with destination: AppDestination) -> Bool {
        guard current == source else { return false }
        entries[index] = destination
        if index > entries.startIndex, entries[entries.index(before: index)] == destination {
            entries.remove(at: index)
            index = entries.index(before: index)
        }
        if canGoForward, entries[entries.index(after: index)] == destination {
            entries.remove(at: entries.index(after: index))
        }
        return true
    }

    mutating func moveBackward(to destination: AppDestination) -> Bool {
        guard destination != current, index > entries.startIndex,
              let match = entries[..<index].lastIndex(of: destination) else { return destination == current }
        index = match
        return true
    }

    mutating func moveForward(to destination: AppDestination) -> Bool {
        let next = entries.index(after: index)
        guard destination != current, next < entries.endIndex,
              let match = entries[next...].firstIndex(of: destination) else { return destination == current }
        index = match
        return true
    }
}
