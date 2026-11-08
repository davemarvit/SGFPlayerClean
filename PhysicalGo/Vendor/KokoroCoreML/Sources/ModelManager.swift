import Foundation

/// Validates CoreML model presence for KokoroCoreML.
enum ModelManager {
    /// Suggested model directory for an application.
    static func defaultDirectory(
        for bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "kokoro-coreml"
    ) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return
            appSupport
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("models")
            .appendingPathComponent("kokoro")
    }

    /// Check whether models exist to run inference.
    ///
    /// Requires `kokoro_frontend.mlmodelc`, `kokoro_backend.mlmodelc`,
    /// and a `voices/` directory.
    static func modelsAvailable(at directory: URL) -> Bool {
        let fm = FileManager.default
        let hasModels =
            fm.fileExists(
                atPath: directory.appendingPathComponent("kokoro_frontend.mlmodelc").path)
            && fm.fileExists(
                atPath: directory.appendingPathComponent("kokoro_backend.mlmodelc").path)
        let hasVoices = fm.fileExists(
            atPath: directory.appendingPathComponent("voices").path)
        return hasModels && hasVoices
    }
}
