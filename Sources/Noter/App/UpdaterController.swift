// ABOUTME: Wraps Sparkle's SPUStandardUpdaterController for menu-triggered and automatic update checks.
// ABOUTME: Exposes the auto-check flag as observable state for the settings toggle.
import Foundation
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class UpdaterController {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var sparkleObservation: NSKeyValueObservation?

    /// Mirrors Sparkle's setting so SwiftUI observes changes; Sparkle persists the value itself.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        // Sparkle can change the setting itself (its first-run permission prompt); mirror it back.
        sparkleObservation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.automaticallyChecksForUpdates != value else { return }
                self.automaticallyChecksForUpdates = value
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
