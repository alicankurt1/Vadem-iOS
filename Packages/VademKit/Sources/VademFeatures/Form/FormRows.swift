import SwiftUI

// Formlarda ortak parçalar: kart (bölüm), alan satırı (+ hata metni) ve seçim listesini açan satır.

// Form ekranlarının ortak ölçüleri.
enum FormLayout {
    // Dokunulan satırların en küçük yüksekliği (dokunma alanı).
    static let minRowHeight: CGFloat = 44
    // Kart içinde satırın üst/alt boşluğu; 44 pt satırla birlikte ~52 pt'lik form satırı verir.
    static let rowVerticalPadding: CGFloat = 4
    // Kartlar arasındaki ve ekran kenarındaki boşluk (Home ile aynı yan boşluk).
    static let spacing: CGFloat = 20
}

/// Formda bir kart: satırları ``SurfaceCard`` ile `vademSurface` zeminde, aralarında ince
/// `vademSeparator` çizgileriyle gösterir.
@MainActor
struct FormCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SurfaceCard(rowVerticalPadding: FormLayout.rowVerticalPadding) {
            content
        }
    }
}

/// Form ekranının kaydırılan gövdesi: kartlar alt alta, `vademBackground` zeminde.
/// Form/List yerine ScrollView: alanlar tek bir Form bölümüne toplanınca denetim, ekranın
/// ortasına düşen son satırları (sil düğmesi, ilk ay) "Dynamic Type kısmen desteklenmiyor"
/// sayıyordu; ScrollView'da bu bulgu yok. ScrollView klavye açılınca içeriği kendiliğinden kaydırır.
@MainActor
struct FormScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormLayout.spacing) {
                content
            }
            // Yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
            .padding(FormLayout.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.vademBackground.ignoresSafeArea())
    }
}

/// Bir alanı ve (varsa) altındaki hata metnini bir ``FormCard`` içinde tek satır olarak gösterir;
/// alan en az 44 pt yüksekliğindedir. `title` verilirse alanın üstünde küçük bir başlık durur.
/// Hata alanla aynı satırda olduğundan aralarında çizgi yoktur. `onTapRow` verilirse satırın boş
/// yerine dokunmak onu çalıştırır. Hata kimliği `<errorIdentifier>` olur (ör. `addInstallment.title.error`).
@MainActor
struct FormField<Content: View>: View {
    var title: String?
    let errorMessage: String?
    let errorIdentifier: String
    // Verilirse satırın boş yerine dokunmak bunu çalıştırır (metin alanına odaklanmak için).
    var onTapRow: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                // Başlık sarılabilen düz metin: AX5'te de kırpılmadan büyür.
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
            }
            // Alan en az 44 pt yüksekliğinde; metin dikeyde ortalanır.
            content
                .frame(minHeight: FormLayout.minRowHeight, alignment: .leading)
            if let errorMessage {
                FieldErrorLabel(message: errorMessage)
                    .accessibilityIdentifier(errorIdentifier)
                    .padding(.bottom, 8)
            }
        }
        .background {
            // Arka plan yalnızca içeriğin boş bıraktığı yerlere dokunulunca çalışır; metin alanı ve
            // düğmeler kendi dokunuşlarını alır. Erişilebilirlikte görünmez (yeni öğe eklemez).
            if let onTapRow {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapRow)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Formun üstündeki kaydetme/silme hatası satırı (``FormCard`` içinde).
@MainActor
struct FormFailureRow: View {
    let message: String

    var body: some View {
        // Label yerine düz metin + gizli simge: Label'ın sabit simge sütunu uzun
        // mesajı denetimde "kırpılmış" gösteriyordu; düz metin satırları sarılarak büyür.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .foregroundStyle(Color.vademTextPrimary)
        .multilineTextAlignment(.leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Alanın altındaki hata metni.
@MainActor
struct FieldErrorLabel: View {
    let message: String

    var body: some View {
        // Hata yalnızca renkle değil, simge ve metinle de belirtilir. Label yerine düz metin + gizli
        // simge: alanla aynı satırda Label'ın sabit simge sütunu denetimde metni "kırpılmış" gösteriyordu.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(Color.vademTextPrimary)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

/// Dokununca seçim listesini iten satır; ok simgesi metin stiliyle Dynamic Type'a göre büyür.
/// Satır bizim çizdiğimiz bir düğme: hazır menü ve gezinme bağlantısı oku denetimde
/// "Dynamic Type desteklenmiyor" sayılıyordu.
@MainActor
struct ChoiceRow: View {
    let title: String
    let value: String
    // VoiceOver ipucu; varsayılan seçim listesini anlatır, gün seçici kendi ipucunu verir.
    var hint = Text("Opens a list", bundle: .module)
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .accessibilityHidden(true)
            }
            // Dokunma alanı ok ve aradaki boşluk dahil tüm satır.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver alan adını etiket, seçili değeri değer olarak okur ("Kart, Everyday card" tek metin değil).
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(hint)
    }

    // Başlık ve değer normal boyutlarda yan yana, erişilebilirlik boyutlarında alt alta durur.
    // ViewThatFits yerine AnyLayout: metinlerin kimliği boyut değişince korunur; aksi halde
    // denetim yeni oluşan metni "Dynamic Type kısmen desteklenmiyor" sayıyor.
    private var label: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title)
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            if !stacked {
                Spacer(minLength: 8)
            }
            Text(value)
                .foregroundStyle(Color.vademTextSecondary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .frame(minHeight: FormLayout.minRowHeight)
        .contentShape(Rectangle())
    }
}

/// Düzenleme formunun en altındaki silme kartı: dokununca `isConfirming` açılır.
/// Onay uyarısı formun kendisine ``SwiftUI/View/deleteConfirmation(isPresented:title:message:identifierPrefix:onDelete:)``
/// ile bağlanır. Kimlik: düğme `<identifierPrefix>.delete`.
@MainActor
struct DeleteSection: View {
    let title: String
    let identifierPrefix: String
    @Binding var isConfirming: Bool

    var body: some View {
        FormCard {
            // Label yerine düz metin + gizli simge: Label'ın sabit simge sütunu denetimde metni
            // "kırpılmış" gösteriyordu. ChoiceRow gibi düz stil ve açık renk: Form'un hazır yıkıcı
            // düğme stili denetimde "Dynamic Type kısmen desteklenmiyor" sayılıyordu.
            Button {
                isConfirming = true
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "trash")
                        .font(.body)
                        .accessibilityHidden(true)
                }
                // Yıkıcı eylem token kırmızısıyla (dueToday); vurgu rengi metinde kullanılmaz.
                .foregroundStyle(Color.vademDueToday)
                .multilineTextAlignment(.leading)
                .frame(minHeight: FormLayout.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix).delete")
        }
    }
}

extension View {
    /// Formun satır içi başlığı: `title` gezinme başlığıdır (geri düğmesi, ekran adı) ve çubuğun
    /// ortasında tek satır olarak çizilir. Vazgeç ile Kaydet arasında yer yetmezse ("Aboneliği düzenle")
    /// metin "…" ile kesilmek yerine biraz küçülür. VoiceOver onu başlık olarak okur.
    func formNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.vademTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            #endif
    }

    /// Silme onayını bu görünüme bağlar. Kimlikler: onay `<identifierPrefix>.delete.confirm`,
    /// vazgeç `<identifierPrefix>.delete.cancel`.
    func deleteConfirmation(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        identifierPrefix: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        // Onay, ortada açılan standart uyarı (alert): confirmationDialog iOS 26'da forma bağlıyken de
        // dar bir açılır pencere (popover) oluyor, Vazgeç düğmesini gizliyor ve kimliği iki kez veriyordu.
        alert(title, isPresented: isPresented) {
            Button(role: .destructive, action: onDelete) { Text("Delete", bundle: .module) }
                .accessibilityIdentifier("\(identifierPrefix).delete.confirm")
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
                .accessibilityIdentifier("\(identifierPrefix).delete.cancel")
        } message: {
            Text(message)
        }
    }
}
