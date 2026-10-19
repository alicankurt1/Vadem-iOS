// Kalıcılık katmanı: SwiftData sadece bu modülde kullanılır. Domain tipleri VademCore'da
// struct olarak kalır; burada @Model kayıtları ve VademCore'daki repository protokollerinin
// SwiftData uygulamaları yer alır.

/// Paylaşılan ayarlar.
public enum VademPersistence {
    /// Uygulama, widget ve App Intents'in aynı veriyi okuduğu App Group.
    /// `Config/Vadem.entitlements` ile aynı olmalı.
    public static let appGroupIdentifier = "group.com.alicankurt.Vadem"
}
