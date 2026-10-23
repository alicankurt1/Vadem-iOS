import AppIntents

/// The Siri phrases and Shortcuts tiles for the two answers; every phrase names the app.
struct VademShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MonthTotalIntent(),
            phrases: [
                "How much do I pay this month in \(.applicationName)",
                "What is my monthly total in \(.applicationName)",
                "How much is due this month in \(.applicationName)",
                "\(.applicationName) monthly total",
            ],
            shortTitle: "Monthly total",
            systemImageName: "turkishlirasign.circle"
        )
        AppShortcut(
            intent: NextPaymentIntent(),
            phrases: [
                "What is my next payment in \(.applicationName)",
                "When is my next payment in \(.applicationName)",
                "What do I pay next in \(.applicationName)",
                "\(.applicationName) next payment",
            ],
            shortTitle: "Next payment",
            systemImageName: "calendar"
        )
    }
}
