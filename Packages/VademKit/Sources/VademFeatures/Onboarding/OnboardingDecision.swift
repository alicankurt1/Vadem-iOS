import Foundation

/// Whether the first-run walkthrough opens at launch.
///
/// A pure decision from the seen version, whether the user already has data and the launch
/// arguments; see ``decide(seenVersion:currentVersion:hasData:launchArguments:)``.
public enum OnboardingDecision: Sendable, Hashable {
    /// Open the walkthrough.
    case show
    /// Do not open it; nothing is saved.
    case hide
    /// Do not open it and save the current version as seen: an existing user who already has data.
    case hideAndMarkSeen

    /// The version of the walkthrough; raising it shows the walkthrough again to users who saw an older one.
    public static let currentVersion = 1

    /// The launch argument that opens the walkthrough at launch, also over sample data (UI tests).
    public static let showLaunchArgument = "-ui-onboarding"
    /// The launch argument that keeps the walkthrough closed at launch (UI tests and captures).
    public static let skipLaunchArgument = "-ui-skip-onboarding"

    /// Decides whether the walkthrough opens.
    ///
    /// In debug builds ``showLaunchArgument`` wins over everything, then ``skipLaunchArgument``
    /// and sample-data launches (`-ui-sample-data` and the inbox arguments) hide it.
    /// Otherwise it shows when `seenVersion` is `nil` or older than `currentVersion` and the
    /// user has no data; with data it is hidden and marked seen (existing users after an update).
    public static func decide(
        seenVersion: Int?,
        currentVersion: Int = OnboardingDecision.currentVersion,
        hasData: Bool,
        launchArguments: [String]
    ) -> OnboardingDecision {
        #if DEBUG
        // Açık istek her şeyden önce gelir: testler örnek verinin üstünde de açabilir.
        if launchArguments.contains(showLaunchArgument) { return .show }
        // Örnek veri ve UI testleri tanıtımı varsayılan olarak atlar; gerçek tercihlere de dokunulmaz.
        let isSampleData = launchArguments.contains(HomeSampleData.launchArgument)
            || InboxView.launchArguments.contains { launchArguments.contains($0) }
        if launchArguments.contains(skipLaunchArgument) || isSampleData { return .hide }
        #endif
        if let seenVersion, seenVersion >= currentVersion { return .hide }
        // Güncellemeden sonra verisi olan kullanıcıya gösterilmez; görüldü sayılır.
        return hasData ? .hideAndMarkSeen : .show
    }
}
