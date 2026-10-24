import VademFeatures
import WidgetKit

/// The WidgetKit-backed ``WidgetReloading``: asks every Vadem widget for a new timeline.
///
/// Lives in the app target so the package never imports WidgetKit.
@MainActor
struct SystemWidgetReloader: WidgetReloading {
    func reloadTimelines() {
        // Uygulama öndeyken istenen yenilemeler widget bütçesinden düşmez.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
