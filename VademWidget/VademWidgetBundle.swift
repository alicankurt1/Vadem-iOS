import SwiftUI
import WidgetKit

/// The widget extension's entry point: every Vadem widget.
@main
struct VademWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingPaymentsWidget()
    }
}
