import SwiftUI

// Formlarda ortak satırlar: alan bölümü (+ hata metni) ve seçim listesini açan satır.

/// Bir alanı ve (varsa) altındaki hata metnini aynı bölümde gösterir.
/// Hata kimliği `<errorIdentifier>` olur (ör. `addInstallment.title.error`).
@MainActor
struct FormFieldSection<Content: View>: View {
    let errorMessage: String?
    let errorIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
            if let errorMessage {
                FieldErrorLabel(message: errorMessage)
                    .accessibilityIdentifier(errorIdentifier)
            }
        }
        .listRowBackground(Color.vademSurface)
    }
}

/// Alanın altındaki hata metni.
@MainActor
struct FieldErrorLabel: View {
    let message: String

    var body: some View {
        // Hata yalnızca renkle değil, simge ve metinle de belirtilir.
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Color.vademTextPrimary)
    }
}

/// Dokununca seçim listesini iten satır; ok simgesi metin stiliyle Dynamic Type'a göre büyür.
/// Satır bizim çizdiğimiz bir düğme: hazır menü ve gezinme bağlantısı oku denetimde
/// "Dynamic Type desteklenmiyor" sayılıyordu.
@MainActor
struct ChoiceRow: View {
    let title: String
    let value: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a list")
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
        .contentShape(Rectangle())
    }
}

/// Düzenleme formunun en altındaki silme bölümü: dokununca onay sorulur, onaylanınca `onDelete` çalışır.
/// Kimlikler: düğme `<identifierPrefix>.delete`, onay `<identifierPrefix>.delete.confirm`,
/// vazgeç `<identifierPrefix>.delete.cancel`.
@MainActor
struct DeleteSection: View {
    let title: String
    let confirmationTitle: String
    let confirmationMessage: String
    let identifierPrefix: String
    let onDelete: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Label(title, systemImage: "trash")
            }
            .accessibilityIdentifier("\(identifierPrefix).delete")
            // Silme geri alınamaz; önce onay istenir.
            .confirmationDialog(confirmationTitle, isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
                    .accessibilityIdentifier("\(identifierPrefix).delete.confirm")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("\(identifierPrefix).delete.cancel")
            } message: {
                Text(confirmationMessage)
            }
        }
        .listRowBackground(Color.vademSurface)
    }
}
