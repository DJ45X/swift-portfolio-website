/// Application metadata.
///
/// A caseless `enum` is used as a static-only namespace so it can't be
/// instantiated. Bump ``version`` manually for each release — CI reads this
/// value to tag the published Docker image.
public enum AppInfo {
    /// The current release version (semver). Bump for each release.
    public static let version = "0.1.0"
}
