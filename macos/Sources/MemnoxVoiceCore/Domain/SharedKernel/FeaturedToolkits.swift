import Foundation

/// The tools the Mac offers before anybody has searched, the same ones the cloud puts first when it suggests a sign in
/// (`memnox-cloud/src/personal/personal-account.ts`): a person's own mail, calendar and documents, then the team tools.
/// Carried here rather than fetched, so they show signed out, when the catalogue cannot be read yet.
public enum FeaturedToolkits {
    public static let slugs = [
        "gmail", "googlecalendar", "googledocs", "googledrive", "outlook", "notion",
        "slack", "github", "linear", "jira",
    ]

    /// The featured tools not connected yet, in the order offered, so a tool already there is never offered again.
    public static func suggested(excluding connected: [ToolConnection]) -> [String] {
        let have = Set(connected.map(\.toolkit))
        return slugs.filter { !have.contains($0) }
    }
}
