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

### Mülakat sorusu: Agent'ın "testler geçti" demesine neden güvenmeyiz?

**Soru:** Bir AI agent'ın "testler geçti" demesine neden güvenmeyiz? Doğrulamayı deterministik bir script'e bırakmanın riskleri ve sınırları neler? Bir agent bu kapıyı nasıl "kandırabilir"?

**Cevap:**
- **Neden güvenmeyiz:** LLM çıktısı olasılıksal. Agent testi hiç koşmadan, eski bir çıktıya bakarak ya da başarısız bir satırı gözden kaçırarak "geçti" diyebilir. Üstelik kodu yazan agent'ın "bitti" demeye eğilimi var (çıkar çatışması). Script ise aynı girdiye her zaman aynı cevabı verir ve exit code yalan söylemez.
- **Script'in sınırları:** Sadece *var olan* testlerin geçtiğini söyler. Test eksikse ya da yanlış şeyi test ediyorsa yeşil anlamsızdır ("yeşil ama yanlış"). Derleme + unit test, UI hatalarını, performansı ve iş kuralının doğru anlaşıldığını yakalamaz. Bu yüzden review ve UI kontrol ayrı adımlar.
- **Agent kapıyı nasıl kandırabilir:**
  - Başarısız testi silmek, `.disabled` / `withKnownIssue` ile susturmak, assertion'ı zayıflatmak (`#expect(true)`).
  - Beklenen değeri koddan kopyalamak (test kodu doğrulamaz, aynalar).
  - Hatalı davranışı özel bir `if test` dalıyla gizlemek, sonucu hardcode etmek.
  - Script'in kendisini, scheme'i ya da build ayarlarını değiştirmek (ör. bir adımı atlatmak).
- **Önlemler:**
  - Testi yazan ve kodu yazan ayrı roller; review agent'ı test diff'ine özellikle bakar.
  - `scripts/`, `.claude/` ve test silme değişiklikleri review'da "yüksek önem" olarak işaretlenir; ileride CI'da bu dosyalara dokunan PR'lar ayrıca uyarı verir.
  - Script CI'da da koşar (Phase 7): yerelde ne denirse densin, son söz temiz bir makinede.
  - Merge her zaman insanda: son kapı otomatik değil.

## Phase 2 — Kodlayıcı + test yazarı agent'ları

- **Subagent nedir:** `.claude/agents/<ad>.md` dosyası. Üstte frontmatter (ad, açıklama, araçlar, model), altta sistem talimatı. Ana oturum (orkestratör) bu agent'a bir görev verir; agent kendi bağlamında çalışır, sonunda tek bir rapor döner.
- **Ayrı bağlam = bağımsızlık:** Test yazarı kodlayıcının düşünce sürecini görmez; sadece issue'yu ve public API'yi görür. Böylece testler kodu "aynalamaz", kabul kriterlerini doğrular.
- **Araç kısıtı ve talimat kısıtı:** `tools:` listesi agent'ın neyi *yapabileceğini*, talimat neyi *yapması gerektiğini* belirler. "Test yazarı production koduna dokunmaz" bir talimat kuralı; review ve diff ile denetlenir.
- **Kabul kriterleri sözleşmedir:** Issue şablonu (`.github/ISSUE_TEMPLATE/task.md`) her işi test edilebilir maddelere böler; iki agent da aynı sözleşmeden çalışır.
- **Metrikler:** `metrics/runs.jsonl` her koşuyu bir satır JSON olarak tutar (süre, kırmızı verify sayısı, yakalanan hata). Vitrin için veri buradan gelecek.

## Phase 3 — Review agent'ı

- **Okuma yetkisi = araç kısıtı:** Reviewer'ın `tools:` listesinde `Edit`/`Write` yok; dosya düzenleyemez. Kodlayıcıdaki "test yazma" kuralı bir talimattı, buradaki kısıt araç seviyesinde. Not: `Bash` hâlâ var (git diff, verify için), yani teorik olarak komutla dosya değiştirebilir; tam izolasyon için ileride Bash'i daraltmak gerekir.
- **Önem seviyeleri:** `blocker` / `major` / `minor` / `nit`. Seviye, pipeline'ın ne yapacağını belirler: blocker+major düzeltilmeden PR açılmaz; minor/nit PR açıklamasına yazılır.
- **`dosya:satır` formatı:** Bulgu doğrulanabilir olmalı. "Şurası kötü" değil, "`Money.swift:42`, -0.005 girdisinde -0.00 döner" gibi.
- **Döngü sınırı:** En fazla 2 review turu. Sınırsız döngü hem maliyet hem "agent'lar birbirini ikna etmeye çalışıyor" riski.
- **Görünür mod (B modu):** Her rol ayrı bir oturumda, yan yana pencerede. Fark: ayrı oturumda `tools:` kısıtı uygulanmaz (oturum tam yetkili), rolü sadece talimat belirler. Subagent modu daha sıkı, görünür mod daha şeffaf.

### Mülakat sorusu: Testler ile code review neyi ayrı yakalar? Aynı model kendi hatasını görebilir mi?

**Soru:** #7'de testler yeşilken review iki bug buldu. Otomatik testler ile code review'un yakaladığı hata türleri nasıl ayrışır? Review'u da bir LLM yapıyorsa "aynı model kendi hatasını göremez" riskine karşı ne yaparsın?

**Cevap:**
- **Testler sözleşmeyi doğrular:** "Yazılan kriter karşılanıyor mu?" sorusunu deterministik ve tekrarlanabilir şekilde cevaplar. Regresyonu yakalar. Ama sadece *düşünülmüş* durumları test eder; kriterde olmayan bir sınır (#7'deki yıl aralığı) testte de yoktur.
- **Review sözleşmenin dışına bakar:** Eksik kriterler, tasarım hataları, API'nin kendi ürettiği ama işleyemediği değerler (`9999-12 + 1 → "10000-01"`), taşma, mimari ihlaller, okunabilirlik, testlerin kalitesi. Yani "doğru şeyi mi yaptık?" sorusu.
- **İkisi birbirini besler:** Review bir açık bulunca, bulgu bir teste dönüşür (#7'de sınır testleri). Böylece aynı hata bir daha review'a kalmaz.
- **"Aynı model kendi hatasını göremez" riskine karşı:**
  - **Bağlam izolasyonu:** Reviewer kodlayıcının gerekçesini görmez; sadece diff + issue. Gerekçeyi görse aynı varsayıma ikna olur.
  - **Farklı talimat ve rol:** Reviewer'ın işi "bitirmek" değil "bulmak"; kontrol listesi ve "kanıt göster" kuralı var (#7'de bulguyu scratch script ile doğruladı).
  - **Farklı model:** Kör noktalar modele özgü olabilir. Review'u farklı bir modelle (ör. Codex) yapmak çeşitlilik sağlar (planda var).
  - **Deterministik araçlar:** Lint, statik analiz, property-based / fuzz testleri LLM'den bağımsız sinyal verir.
  - **İnsan kapısı:** Merge her zaman insanda; LLM review, insan review'unu hızlandırır, yerine geçmez.
- **Ölçmek:** Hangi hatayı kimin yakaladığını metriklerde tutmak (`bugs_caught_by_tests`, `review_findings`) hangi kapının işe yaradığını gösterir.

## Phase 4 — UI kontrol agent'ı

- **Yine "yakalayan script, karar veren agent":** `scripts/ui-check.sh` simülatörde `UICheckTests`'i koşar, ekran görüntülerini `.xcresult`'tan çıkarır. Agent sadece görüntülere bakıp yorum yapar. Ekran görüntüsü almayı LLM'e bırakmak yavaş ve kırılgan olurdu.
- **XCUITest attachment'ları:** `XCTAttachment(screenshot:)` + `lifetime = .keepAlways` → görüntü result bundle'a girer; `xcrun xcresulttool export attachments` ile dosya olarak çıkar.
- **Varyantlar:** `XCUIDevice.shared.appearance` ile açık/koyu mod, `-UIPreferredContentSizeCategoryName` launch argümanı ile Dynamic Type (AX5 = en büyük erişilebilirlik boyutu). Tek ekran × 3 varyant.
- **`performAccessibilityAudit()` (iOS 17+):** Apple'ın deterministik erişilebilirlik denetimi: kontrast, eksik etiket, dokunma alanı, Dynamic Type, kırpılan metin. İlk koşuda gerçek bir bulgu verdi: açık modda gri `v0.1.0` yazısının kontrastı sınırda ("Contrast nearly passed").
- **İki katman:** Denetim kural tabanlı sorunları bulur; agent ise kuralın göremediklerini (yanlış veri, garip boşluk, koyu modda kaybolan öğe) görür.
- **Maliyet:** Simülatör koşusu ~2 dk; bu yüzden UI kontrol sadece diff UI'a dokunuyorsa çalışır.
