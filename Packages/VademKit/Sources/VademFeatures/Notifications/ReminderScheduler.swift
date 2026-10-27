import Foundation
import VademCore

/// Keeps the pending reminders in step with the saved payments, using ``NotificationPlanner``.
///
/// ``refresh()`` first reads the ``ReminderPreferences``: when reminders are off it clears the
/// pending reminders and never asks for permission. Otherwise it plans the timing's kinds and then:
/// - nothing to plan: clears the pending reminders;
/// - permission not asked yet: asks (only when there is something to send), schedules if granted;
///   after an answer it never asks again in this process, but a request that throws (no answer,
///   e.g. the scene was not active) is retried on the next refresh;
/// - denied: does nothing and never asks again;
/// - allowed: replaces the pending reminders with the plan.
///
/// Reminders are best effort: repository and center errors are ignored.
@MainActor
public final class ReminderScheduler {
    private let repository: any PaymentRepository
    private let center: any ReminderCenter
    private let preferences: any ReminderPreferencesStore
    private let calendar: Calendar
    private let now: () -> Date
    private let formatAmount: (Money) -> String

    // Bu oturumda izin isteği bir cevap aldı; cevap ne olursa olsun tekrar sorulmaz.
    // İstek hata verirse (cevap yok) bayrak konmaz, sonraki yenileme yeniden sorar.
    private var hasRequestedAuthorization = false
    // Aynı anda iki yenileme izin penceresini iki kez açmasın: süren yenileme bir tur daha yapar.
    private var isRefreshing = false
    private var needsAnotherPass = false

    /// Creates a scheduler; `preferences` is read on every ``refresh()`` (default: the
    /// `UserDefaults` store), `now` is the clock and `formatAmount` formats the amounts in the body.
    public init(
        repository: any PaymentRepository,
        center: any ReminderCenter,
        preferences: any ReminderPreferencesStore = UserDefaultsReminderPreferencesStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() },
        formatAmount: @escaping (Money) -> String = AmountText.format
    ) {
        self.repository = repository
        self.center = center
        self.preferences = preferences
        self.calendar = calendar
        self.now = now
        self.formatAmount = formatAmount
    }

    /// Plans the reminders from the repository and updates the center (see the type's rules).
    public func refresh() async {
        guard !isRefreshing else {
            needsAnotherPass = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsAnotherPass = false
            await refreshOnce()
        } while needsAnotherPass
    }

    private func refreshOnce() async {
        // Tercihler her turda okunur: ayar değişince bir sonraki yenileme hemen uyar.
        let settings = preferences.load()
        guard settings.isEnabled else {
            // Hatırlatmalar kapalı: bekleyenler temizlenir, izin hiç sorulmaz.
            try? await center.replacePending([])
            return
        }

        let reminders: [PlannedReminder]
        do {
            reminders = NotificationPlanner.plan(
                now: now(),
                calendar: calendar,
                cards: try repository.cards(),
                installments: try repository.installments(),
                subscriptions: try repository.subscriptions(),
                kinds: settings.timing.kinds,
                formatAmount: formatAmount
            )
        } catch {
            // Veri okunamazsa bekleyen hatırlatmalara dokunulmaz.
            return
        }

        // Planlanacak bir şey yoksa izin sorulmaz; eski hatırlatmalar temizlenir.
        guard !reminders.isEmpty else {
            try? await center.replacePending([])
            return
        }

        switch await center.authorizationStatus() {
        case .allowed:
            try? await center.replacePending(reminders)
        case .denied:
            // Kullanıcı reddetti: ısrar edilmez.
            return
        case .notDetermined:
            guard !hasRequestedAuthorization else { return }
            let granted: Bool
            do {
                granted = try await center.requestAuthorization()
            } catch {
                // İstek cevap almadan bitti (ör. sahne etkin değildi): soru sorulmuş sayılmaz,
                // sonraki yenileme (kayıt ya da öne gelme) yeniden dener.
                return
            }
            // Bayrak ancak cevaptan sonra konur; cevap ne olursa olsun bu oturumda tekrar sorulmaz.
            hasRequestedAuthorization = true
            if granted {
                try? await center.replacePending(reminders)
            }
        }
    }
}
