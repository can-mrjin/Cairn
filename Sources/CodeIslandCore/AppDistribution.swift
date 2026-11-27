import Foundation

/// Links into the project's GitHub releases.
public enum ReleaseNotesLink {
    /// Same repository the Sparkle feed (`SUFeedURL` in Info.plist) and every
    /// appcast `<link>` point at.
    public static let repositoryURL = "https://github.com/can-mrjin/Cairn"

    /// The release page for `version`. Releases are tagged `v<version>`
    /// (`releases/tag/v1.0.34`, see appcast.xml). Anything that cannot be a
    /// tag — empty, whitespace inside, a stray URL — opens the release list
    /// instead of a 404.
    public static func url(forVersion version: String) -> URL {
        var tag = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-+")
        guard let first = tag.unicodeScalars.first,
              CharacterSet.decimalDigits.contains(first),
              tag.unicodeScalars.allSatisfy(allowed.contains) else {
            return URL(string: repositoryURL + "/releases")!
        }
        return URL(string: repositoryURL + "/releases/tag/v" + tag)!
    }
}

/// Where the running app bundle lives, as far as self-updating is concerned.
///
/// Sparkle replaces the bundle in place, so it cannot update a copy it is not
/// allowed to write: one macOS launched through App Translocation (a
/// quarantined app opened where it was downloaded or unpacked, which runs from
/// a randomized read-only mount), one running straight from the mounted DMG,
/// or one on any other read-only volume. Updates then fail with an error that
/// never mentions the fix — moving the app into Applications.
public enum AppInstallLocation {
    public enum ReadOnlyReason: Equatable, Sendable {
        /// macOS runs a translocated copy under `/AppTranslocation/`.
        case translocated
        /// Running from a mounted disk image (a read-only volume under /Volumes).
        case diskImage
        /// Some other read-only volume.
        case readOnlyVolume
    }

    /// Pure classification; the caller supplies the volume's read-only flag
    /// (`URLResourceValues.volumeIsReadOnly`) so this stays testable.
    ///
    /// Translocation is checked first: its mount is read-only as well, and it
    /// needs a different explanation than "you opened the DMG".
    public static func readOnlyReason(bundlePath: String, volumeIsReadOnly: Bool) -> ReadOnlyReason? {
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        guard volumeIsReadOnly else { return nil }
        if bundlePath.hasPrefix("/Volumes/") { return .diskImage }
        return .readOnlyVolume
    }
}

/// Channel selection rules shared by Sparkle (`allowedChannels(for:)`) and
/// release tooling (`scripts/update-appcast.sh`).
public enum UpdateChannelPolicy {
    public static let betaChannel = "beta"

    /// True when `version` carries a SemVer prerelease suffix such as
    /// `1.3.0-beta.1`, `1.3.0-rc.1`, or `1.3.0-alpha`.
    public static func isPrereleaseVersion(_ version: String) -> Bool {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hyphen = trimmed.firstIndex(of: "-") else { return false }
        let afterHyphen = trimmed[trimmed.index(after: hyphen)...]
        let prerelease = afterHyphen.split(separator: "+", maxSplits: 1).first ?? ""
        return !prerelease.isEmpty
    }

    /// Users running a beta build opt into the beta channel by default so they
    /// keep receiving follow-up beta fixes; stable builds default to stable only.
    public static func defaultIncludeBetaUpdates(currentVersion: String) -> Bool {
        isPrereleaseVersion(currentVersion)
    }

    /// Sparkle channels enabled for the given preference. Returning an empty set
    /// restricts Sparkle to the default (stable) channel; adding `"beta"` opts
    /// into `<sparkle:channel>beta</sparkle:channel>` items as well.
    public static func allowedChannels(includeBetaUpdates: Bool) -> Set<String> {
        includeBetaUpdates ? [betaChannel] : []
    }
}
