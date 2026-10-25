import SwiftUI

/// The assistant chat: questions about the user's payments, answered on device.
///
/// User bubbles sit on the trailing side (`vademAccent`), answers on the leading side
/// (`vademSurface`). Each message (`assistant.message.<index>`) is one VoiceOver element, read in
/// order. Suggestion chips (`assistant.suggestion.<index>`), the input (`assistant.input`), the send
/// button (`assistant.send`) and a footer note (`assistant.footer`) complete the chat. Without
/// messages an empty state (`assistant.empty`) says the assistant is read-only. When the model is
/// unavailable, an explanation (`assistant.unavailable`) replaces the chat. Closing the screen
/// cancels the question in flight. No continuous animation under Reduce Motion or `-ui-static-motion`.
@MainActor
public struct AssistantView: View {
    /// The launch argument that opens Home with the assistant already pushed (debug builds).
    public nonisolated static let launchArgument = "-ui-assistant"
    /// With `-ui-sample-data`: a scripted, available assistant with canned answers for the chips.
    public nonisolated static let scriptedLaunchArgument = "-ui-scripted-assistant"
    /// With `-ui-sample-data`: an assistant that is unavailable (Apple Intelligence off).
    public nonisolated static let unavailableLaunchArgument = "-ui-assistant-unavailable"

    @State private var model: AssistantViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    // Son mesajın kaydırma hedefi.
    private static let bottomAnchor = "assistant.bottom"

    /// Creates the screen for `model`.
    public init(model: AssistantViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            if let message = model.unavailableMessage {
                unavailableView(message)
            } else {
                chat
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
        .navigationTitle("Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Home gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .onAppear { model.refreshAvailability() }
        // Ekran kapanınca bekleyen soru iptal edilir; sohbet saklanmaz.
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("assistant.screen")
    }

    // MARK: Sohbet

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.messages.isEmpty {
                        emptyState
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        bubble(message)
                            .accessibilityIdentifier("assistant.message.\(index)")
                    }
                    if model.isResponding {
                        thinking
                    }
                    suggestions
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                        .id(Self.bottomAnchor)
                }
                // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.isResponding) {
                // "Thinking…" satırı da görünür olsun.
                scrollToBottom(proxy)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
    }

    // Yeni mesaj görünür olsun; Reduce Motion veya -ui-static-motion açıkken animasyonsuz.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityHidden(true)
            Text("Ask about your payments")
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
            Text(AssistantViewModel.readOnlyNote)
                .font(.body)
                .foregroundStyle(Color.vademTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant.empty")
    }

    private func bubble(_ message: AssistantViewModel.Message) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.body)
                .foregroundStyle(isUser ? Color.vademOnAccent : Color.vademTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Color.vademAccent : Color.vademSurface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if !isUser { Spacer(minLength: 40) }
        }
        // VoiceOver her mesajı tek öğe olarak, kimin yazdığıyla birlikte okur.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.accessibilityLabel)
    }

    // Cevap beklenirken: yazma animasyonu yok; sabit metin, hareket izinliyse yanında dönen gösterge.
    private var thinking: some View {
        HStack(spacing: 8) {
            if Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested) {
                ProgressView()
                    .accessibilityHidden(true)
            }
            Text("Thinking…")
                .font(.body)
                .foregroundStyle(Color.vademTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant.thinking")
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(AssistantViewModel.suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    model.send(suggestion: suggestion)
                } label: {
                    Label(suggestion, systemImage: "sparkles")
                        .font(.body)
                        .foregroundStyle(Color.vademTextPrimary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44, alignment: .leading)
                        .background(Color.vademSurface, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isResponding)
                .accessibilityIdentifier("assistant.suggestion.\(index)")
            }
        }
        .padding(.top, 8)
    }

    // MARK: Giriş

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a question", text: $model.input, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .foregroundStyle(Color.vademTextPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .disabled(model.isResponding)
                    .accessibilityLabel("Question")
                    .accessibilityIdentifier("assistant.input")
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademOnAccent)
                        // En az 44 pt dokunma alanı.
                        .frame(width: 44, height: 44)
                        .background(Color.vademAccent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .opacity(model.canSend ? 1 : 0.5)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("assistant.send")
            }
            Text(AssistantViewModel.footerNote)
                .font(.footnote)
                .foregroundStyle(Color.vademTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistant.footer")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.vademBackground)
    }

    // MARK: Kullanılamıyor

    private func unavailableView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
                Text("Assistant unavailable")
                    .font(.headline)
                    .foregroundStyle(Color.vademTextPrimary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("assistant.unavailable")
        }
    }
}
