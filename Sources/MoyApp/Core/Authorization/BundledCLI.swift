import Foundation

/// Resolve the embedded CLI by its build-time location. Auxiliary executable lookup
/// can match the app's "Moy" executable when searching for "moy" on a case-insensitive volume.
enum BundledCLI {
    static func executableURL(in bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appending(path: "Contents/Helpers/moy")
    }
}
