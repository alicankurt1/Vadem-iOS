# Öğrenme Notları

Her fazda öğrenilen kavramlar ve mülakat soruları.

## Phase 0 — Foundation

- **Yerel Swift Package ile modülerlik:** İş kuralları (`VademCore`) UI'dan ayrı bir modülde. Modül sınırı, bağımlılık yönünü derleyiciye zorlatır: Core, SwiftUI'yi göremez.
- **`swift test` ile simülatörsüz test:** Package macOS'u da desteklediği için domain testleri saniyeler içinde koşar.
- **xcconfig:** Build ayarları metin dosyasında, diff'lenebilir. Team ID gibi kişisel değerler git-ignore'lu `Local.xcconfig`'te.
- **Default actor isolation kapalı:** Xcode 26 yeni projelerde her şeyi varsayılan olarak `@MainActor` yapıyor; biz kapatıp izolasyonu açıkça yazıyoruz.

### Mülakat sorusu: Default actor isolation — `MainActor` mı, `nonisolated` mı?

**Soru:** Swift 6'da `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ile `nonisolated` arasındaki trade-off nedir? Domain modülünü neden açıkça `nonisolated` tutuyoruz?

**Cevap:**
- **`MainActor` varsayılanı:** İşaretsiz her tip ve fonksiyon main actor'e bağlanır. UI ağırlıklı, tek thread'li uygulamalarda concurrency hatalarını neredeyse sıfırlar; "approachable concurrency" fikri bu. Bedeli: arka planda çalışması gereken kod da main'e kilitlenir. Kaçmak için her yere `nonisolated` / `@concurrent` yazmak gerekir, yanlışlıkla ağır iş main thread'de koşabilir.
- **`nonisolated` varsayılanı:** Kod hiçbir actor'e bağlı değildir. UI kodu `@MainActor`'ü açıkça yazar; izolasyon kodu okurken görünür olur. Bedeli: daha fazla anotasyon ve derleyicinin daha fazla `Sendable` uyarısı.
- **Domain neden `nonisolated`:** İş kuralları saf hesaplamadır (taksit takvimi, toplamlar). Widget, App Intent, arka plan bildirimi gibi main thread'de olmayan bağlamlardan da çağrılacak. Değer tipleri (`struct`, `Sendable`) olarak tasarlanınca her yerden güvenle çağrılır ve `swift test` ile actor kurulumu olmadan test edilir.
- **Kural:** İzolasyon bir tasarım kararıdır, varsayılana bırakılmaz. UI → `@MainActor`, domain → saf ve `Sendable`, paylaşılan değişken durum → kendi `actor`'ü.

## Phase 1 — Doğrulama script'i

- **Deterministik kapı:** Agent "testler geçti" diyemez; karar `scripts/verify.sh`'ın son satırı (`VERIFY: PASS/FAIL`) ve exit code'udur. LLM çıktısı değişken, script çıktısı değil.
- **`build-for-testing`:** Uygulama ve test target'larını simülatör açmadan derler; kırık bir UI testi de derleme hatası olarak yakalanır.
- **Shared scheme:** `xcshareddata/xcschemes` altında versiyonlanır; agent'lar ve CI aynı scheme'i görür. Kişisel scheme'ler `xcuserdata`'da kalır (gitignore).
- **Skill vs script:** Script *ne* yapılacağını garanti eder; `/verify` skill'i agent'a *nasıl* raporlayacağını ve kuralları (testi zayıflatma yok) söyler.
- **Makine okunur özet:** `last-run.json` ileride pipeline metriklerinin (süre, kırmızı/yeşil) kaynağı olacak.
