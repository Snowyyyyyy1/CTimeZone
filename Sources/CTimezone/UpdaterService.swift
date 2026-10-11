import Combine
import Foundation
import Sparkle

/// In-app updates through Sparkle.
///
/// Updates are trusted through the EdDSA signature in the appcast, checked
/// against `SUPublicEDKey`, not through an Apple certificate, so ad-hoc
/// signed builds can still update themselves safely.
///
/// When a copy cannot update correctly, the whole path stays off instead of
/// running an updater that would fail halfway.
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    enum Availability: Equatable {
        case available
        /// Running from a build directory rather than an installed app.
        case buildProducts
        /// Sparkle replaces the bundle in place, so it must live in an
        /// Applications folder, not a DMG or Downloads.
        case notInstalled
        case missingPublicKey

        var reason: String? {
            switch self {
            case .available: nil
            case .buildProducts: String(localized: "Development builds do not update themselves.")
            case .notInstalled: String(localized: "Move CTimeZone to Applications to enable updates.")
            case .missingPublicKey: String(localized: "This build has no update signing key.")
            }
        }
    }

    let availability: Availability
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    private init() {
        availability = Self.resolveAvailability(bundle: .main)
        guard availability == .available else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private static func resolveAvailability(bundle: Bundle) -> Availability {
        let path = bundle.bundleURL.standardizedFileURL.path
        let buildSegments = ["/.build/", "/DerivedData/", "/Build/Products/"]
        if buildSegments.contains(where: path.contains) { return .buildProducts }

        let roots = [
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask),
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        ]
        .flatMap { $0 }
        .map { $0.standardizedFileURL.path }
        guard roots.contains(where: { path.hasPrefix($0 + "/") }) else { return .notInstalled }

        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return .missingPublicKey }
        return .available
    }
}
