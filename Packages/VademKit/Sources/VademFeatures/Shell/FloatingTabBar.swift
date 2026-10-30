import SwiftUI

/// The floating tab bar: a glass capsule with one button per ``AppTab`` and a separate round ＋ button.
///
/// The selected tab carries a highlight pill that slides to a newly selected tab
/// (`matchedGeometryEffect`) with a light haptic; under Reduce Motion or `-ui-static-motion` it
/// moves without animation. Tabs read as buttons with the selected trait. At accessibility text
/// sizes the labels hide (icons only), the bar stops growing so it never overflows, and a long
/// press shows the Large Content Viewer. Identifiers: see ``AppTab``.
@MainActor
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    @Namespace private var pillNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Çubuk bu boyuttan sonra büyümez; daha büyük yazıda Large Content Viewer devreye girer.
    private static let maxTypeSize = DynamicTypeSize.xLarge
    private static let pillID = "tab.pill"

    var body: some View {
        HStack(spacing: 12) {
            tabCapsule
            addButton
        }
        // Erişilebilir boyutlarda simgeler sabit kalır; etiketler gizlenir (aşağıda).
        .dynamicTypeSize(...Self.maxTypeSize)
        // Ekran kenarlarından içeride: sol 4 pt şeritte her zaman ekran arka planı kalır.
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
    }

    // Erişilebilir yazı boyutlarında yalnızca simgeler gösterilir.
    private var showsLabels: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var tabCapsule: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .vademGlass()
        .overlay {
            // İnce çerçeve: cam açık zeminde de ayrışır.
            Capsule().strokeBorder(Color.vademSeparator, lineWidth: 1)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            select(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.body.weight(.semibold))
                    .imageScale(.medium)
                if showsLabels {
                    Text(tab.title)
                        .font(.caption2.weight(isSelected ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // Seçili sekme koyu hero hapında açık yazıyla (çift kontrast testinde güvencede).
            .foregroundStyle(isSelected ? Color.vademHeroText : Color.vademTextPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            // En az 44 pt dokunma alanı.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.vademHero)
                        .matchedGeometryEffect(id: Self.pillID, in: pillNamespace)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: tab.systemImage)
            Text(tab.title)
        }
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    // Ekleme sayfasını her sekmeden açan yuvarlak ＋ düğmesi.
    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.vademOnAccent)
                .frame(width: 56, height: 56)
                .background(Color.vademAccent, in: Circle())
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add", bundle: .module))
        .accessibilityShowsLargeContentViewer {
            Image(systemName: "plus")
            Text("Add", bundle: .module)
        }
        .accessibilityIdentifier(AppTab.addIdentifier)
    }

    // Hap yeni sekmeye kayar; Reduce Motion veya -ui-static-motion açıkken animasyonsuz.
    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            selection = tab
        }
    }
}
