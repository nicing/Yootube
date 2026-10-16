import Combine
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        let updater = controller.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }
}
