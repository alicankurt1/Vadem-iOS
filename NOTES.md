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

### Phase 4 düzeltmesi — Pipeline kendi ölçüm aletinde hata buldu

#10 koşusunda UI check ve review agent'ları, ürünü değil **test altyapısını** yakaladı:
- **Koyu mod hiç uygulanmıyordu:** `XCUIDevice.shared.appearance` bu ortamda etkisizdi; koyu ve açık görüntüler byte byte aynıydı. Çözüm: görünümü test dışından `xcrun simctl ui <udid> appearance dark` ile ayarlamak ve testi her görünüm için ayrı koşmak (`build-for-testing` bir kez, `test-without-building` iki kez). Test, `TEST_RUNNER_` önekiyle verilen ortam değişkeninden hangi görünümde olduğunu öğreniyor.
- **Hatalar eksik sayılıyordu:** `xcresulttool get test-results summary` test başına sadece **ilk** hatayı veriyor. İlk Phase 4 koşusunda "1 sorun" dedik; gerçekte "Label not human-readable" de vardı ama gizlenmişti. Çözüm: `get test-results tests` ağacındaki her `Failure Message` düğümünü okumak.
- **Zayıf koruma:** Koyu modu iki PNG'nin byte karşılaştırmasıyla kontrol etmek, saat değişirse yanlış yere geçer. Çözüm: durum çubuğundan uzak bir pikselin parlaklığına bakmak.
- **Ders:** Ölçüm aletini de ölçmek gerekir. "0 sorun" çıktısı, aletin sorunları görebildiği kanıtlanmadıkça anlamsızdır. Bilinen bir hatayla (ana ekrandaki kontrast) aleti doğruladık: düzeltmeden sonra aynı ekranda 4 sorunun hepsi görünüyor.
- **Süreç:** Altyapı düzeltmesi ürün issue'sunun branch'ine girmedi; reviewer'ın kapsam uyarısı üzerine ayrı bir PR oldu.

### Koşu #10 — Sürüm etiketi kontrastı ve okunabilirliği

- **Ne yapıldı:** Kök ekrandaki `v0.1.0` yazısı `.subheadline` + `.primary` stilinde `Version 0.1.0` oldu; `UICheckTests` her varyantta etiketin metnini (`^Version x.y.z$`), dokunulabilirliğini ve başlığın altında/daha küçük olduğunu kontrol ediyor (PR #12).
- **UI check kapısı:** 1. turda `Label not human-readable — 'v0.1.0'` (önceden harness tarafından gizlenmişti). Ayrı bir `accessibilityLabel("Version …")` eklemek 2. turda yeni bir hata doğurdu: `Text clipped`. Denetim, görünen metin ile okunan etiket uyuşmayınca bunu kırpılma olarak sayıyor. Çözüm: görünen metnin kendisini okunabilir yapmak.
- **Tasarım kararı:** `.secondary` açık modda kontrast denetimini geçemiyor; hiyerarşiyi renk yerine boyut ve konum taşıyor (minor bulgu olarak kabul edildi).
- **Metrikler:** ~29 dk, 11 verify koşusu, 3 düzeltme turu; review 1 major / 2 minor / 3 nit, UI check 5 major / 1 minor / 2 nit (major'ların 3'ü harness hatasıydı, PR #11).
- **Ders:** Erişilebilirlik etiketini görünen metinden farklı yapmak bir yamadır; asıl düzeltme görünen metni anlaşılır kılmaktır.

### Mülakat sorusu: Ekran görüntüsünü agent'a değerlendirtmek ile kural tabanlı denetim

**Soru:** UI testlerinde ekran görüntüsünü bir agent'a değerlendirtmek ile `performAccessibilityAudit()` gibi kural tabanlı bir denetim arasındaki fark nedir? Birbirinin yerini tutar mı? Ölçüm aletinin kendisi hatalıyken bunu nasıl fark ettik?

**Cevap:**
- **Kural tabanlı denetim:** Deterministik, hızlı, tekrarlanabilir. Kontrast oranı, eksik/anlamsız etiket, dokunma alanı, kırpılan metin, Dynamic Type gibi *ölçülebilir* kuralları kontrol eder. Aynı ekran her seferinde aynı sonucu verir; kapı (gate) olmaya uygundur.
- **Agent değerlendirmesi:** Kuralın tanımlayamadığı şeyleri görür: görsel hiyerarşi, yanlış/placeholder veri, koyu modda "teknik olarak geçen ama kötü görünen" öğe, iki görüntünün aynı olması gibi tutarsızlıklar. Ama olasılıksaldır; kapı değil, danışman olarak kullanılır.
- **Yerini tutmazlar, tamamlarlar:** Denetim "kural ihlali var mı?", agent "bu ekran doğru ve iyi mi?" sorusunu cevaplar. #10'da kontrast ve kırpılma bulgularını denetim, hiyerarşi zayıflığını ve koyu modun hiç uygulanmadığını agent buldu.
- **Hatalı ölçüm aletini nasıl fark ettik:**
  - Agent, kurala değil **tutarlılığa** baktı: koyu ve açık görüntünün MD5'i aynıydı. Kural tabanlı denetim bunu asla söylemezdi; "0 sorun" demeye devam ederdi.
  - Agent ham veriye (result bundle) inip script'in özetiyle karşılaştırdı: script 1 hata dedi, bundle'da 4 vardı.
  - Düzeltmeden sonra aleti **bilinen bir hatayla** doğruladık: eski ekranda beklenen 4 sorunun hepsi göründü, koyu görüntü gerçekten koyu çıktı.
- **Ders:** Her kapının kendi doğrulaması olmalı (koyu modu piksel ile kontrol etmek gibi "aletin aleti"). Ve "yeşil" sonuç, aletin kırmızıyı görebildiği kanıtlanmadan güven vermez.

## Phase 5 — Orkestratör (`/ship`) ve yazar agent'ı

- **Skill = prosedür, agent = rol:** `/ship` bir agent değil; ana oturumun (orkestratör) izlediği adım adım prosedür. Agent'lar (coder, test-writer, reviewer, ui-checker, writer) bu prosedürün çağırdığı roller.
- **Yetki kapsamı:** `/ship #N` yazmak, *sadece o issue için* agent commit'leri, branch push'u, PR ve metrik commit'i için izin demek. Merge yine insanda. İnsan kapıları: başta plan onayı, sonda merge.
- **Eskalasyon kuralları:** Döngü sınırları (verify 3, review 2), fabrika bulgusu, rol dışı dosya değişikliği → durup sor. Otomasyonun "ne zaman durması gerektiğini" bilmesi, ne zaman devam edeceğini bilmesi kadar önemli.
- **Yazar agent'ı (`/after-merge #P`):** Merge'den sonra CHANGELOG (kullanıcı gözüyle ne değişti), README (sadece görünür değişiklik varsa) ve NOTES'u (koşudan bir ders çıktıysa) günceller. Ayrı bir `docs/pr-P` branch'inde küçük bir PR açar. Neden merge sonrası? Dokümanın anlattığı şey, gerçekten `main`'e girmiş olan kod olmalı.
- **Fabrika ayrımı kurala dönüştü:** #10'daki ders artık `/ship` prosedüründe yazılı: altyapı bulgusu issue branch'inde düzeltilmez.

### Koşu #15 — Taksit planı ve yuvarlama kararı (ADR-0001)

- **Ne yapıldı:** `VademCore`'a `InstallmentPlan` eklendi: toplam tutarı 1–36 aylık taksite böler; ödeme takvimi saklanmaz, `firstMonth`'tan hesaplanır. İlk `/ship` koşusu (test yazarı görünür oturumda, coder ve reviewer subagent olarak) (PR #16).
- **Tasarım kararı (ADR-0001):** Her taksit toplam / adet, kuruşa **aşağı** yuvarlanır; artan kuruşlar **ilk** taksite eklenir (`1000.00 / 3 → 333.34, 333.33, 333.33`). Toplam her zaman tam tutar. Artanı son taksite koymak da aynı derecede doğruydu ama Türk kart ekstrelerinde daha az tanıdık olduğu için reddedildi.
- **Review kapısı:** 9999-12'ye yakın başlayan bir plan oluşturulabiliyor (ya da JSON'dan çözülebiliyor), sonra `lastMonth` / `payments` çöküyordu. Kriterlerde olmayan bu sınırı testler değil review yakaladı; init'e "son taksit 9999-12'den sonra olamaz" kuralı eklendi. Ayrıca geçersiz JSON'un reddedildiğini gösteren test eksikti.
- **Metrikler:** ~32 dk, 7 verify koşusu, 1 düzeltme turu; review 0 blocker / 0 major / 2 minor / 4 nit (2 nit açık bırakıldı), UI check atlandı (sadece domain).
- **Ders:** #7'deki yıl sınırı dersi tekrarlandı: bir tipin desteklediği aralık, onu kullanan her yeni tipte yeniden sınanmalı. Decoding de failable init'ten geçmeli; yoksa doğrulama JSON yolundan atlatılır.

## Phase 6 — Vitrin

- **README bir vitrin:** Projeyi ilk kez gören biri 30 saniyede şunu anlamalı: ne yapıyor, pipeline nasıl akıyor (Mermaid diyagramı, GitHub'da render olur), roller ve kurallar, gerçekte ne yakalandı, sayılar.
- **Metrikler veriden üretilir:** `scripts/metrics-report.sh --update-readme`, `metrics/runs.jsonl`'dan tabloyu yeniden yazar. Elle yazılan rakam eskir; script'le üretilen güncel kalır. README'deki `<!-- metrics:start -->` işaretleri script'in nereye yazacağını belirler.
- **Hikâye > özellik listesi:** "5 agent'ım var" yerine "testler yeşilken reviewer şunu buldu" ve "test altyapısının kendisi bozuktu" gibi somut olaylar daha ikna edici.
- **Dürüst sayılar:** 4 koşu, 71 dakika, 0 kırmızı verify (agent'lar kendi koşularında düzeltiyor), 5 düzeltme turu. Abartısız, kaynağı repoda.

## Phase 9 — Kalıcılık temeli (fabrika kısmı)

- **Neden ayrı modül:** `VademPersistence` SwiftData'yı import eden tek modül. `VademCore` saf kalıyor; repository protokolleri Core'da, uygulamaları Persistence'ta. Ekranlar protokolü tanır, SwiftData'yı tanımaz (**DIP**). Testlerde sahte depo, uygulamada SwiftData.
- **Domain struct, kayıt sınıfı ayrı:** SwiftData `@Model` sınıf ister; domain tiplerimiz değer tipi (`struct`, `Sendable`). Aradaki dönüşüm (mapping) Persistence'ta yapılır, domain tipleri depolamaya göre şekil değiştirmez.
- **İlk günden versiyonlu şema:** `VersionedSchema V1` + `SchemaMigrationPlan`. Yayınlanmış bir şema yerinde değiştirilmez, yeni versiyon eklenir; yoksa kullanıcı verisi güncellemede kaybolabilir.
- **App Group:** Veri baştan `group.com.alicankurt.Vadem` container'ında. Widget ve Siri (Phase 13) aynı veriyi okuyacak; sonradan taşımak migration demek.
- **Hedefe özel xcconfig:** Entitlements sadece uygulama hedefinde olmalı (test bundle'larında değil). `App.xcconfig`, `Shared.xcconfig`'i include edip sadece uygulamaya `CODE_SIGN_ENTITLEMENTS` ekliyor.

### Koşu #26 — Depolama sözleşmesi (`PaymentRepository`)

- **Ne yapıldı:** `VademCore`'a `InstallmentItem`, `SubscriptionItem`, `PaymentRepository` protokolü ve referans uygulama `InMemoryPaymentRepository` eklendi. SwiftData yok; testler protokol üzerinden (`any PaymentRepository`) **sözleşme testi** olarak yazıldı, sonraki issue'da SwiftData uygulaması aynı senaryolardan geçecek (PR #27).
- **Review kapısı:** Sıralama kuralı sadece "büyük/küçük harfe duyarsız" diyordu, hangi karşılaştırma olduğunu söylemiyordu. `caseInsensitiveCompare` ile `localizedStandardCompare` Türkçe noktasız ı'lı "ılık" kelimesini farklı sıralar; SwiftData uygulaması ikisinden birini seçebilirdi. Kural dokümanda adıyla yazıldı ve bir sözleşme senaryosu eklendi. Taksit ve abonelikte başlık eşitliğinde `id` ile ayırma da test edilmemişti; sözlük tabanlı bir depo bu hatayı gizlerdi.
- **Metrikler:** ~11 dk, 8 verify koşusu (0 kırmızı), 1 düzeltme turu; review 0 blocker / 0 major / 3 minor / 1 nit, UI check atlandı (sadece domain).
- **Ders:** Bir sözleşmeyi ikinci uygulama yazılmadan **önce** sıkılaştırmak ucuz; sonra yapılırsa iki uygulamadan biri "yanlış" olur. Sözleşmede "bir şekilde sırala" yetmez, kullanılan API adıyla yazılmalı ve belirsiz durumu (eşitlik, yerel ayar) bir test sabitlemeli.
- **Sonraki adım için not:** Sözleşme testleri `VademCoreTests` içinde; test hedefleri birbirini import edemez, bu yüzden `VademPersistenceTests` bunları kullanabilsin diye ortak bir test-destek hedefi gerekecek.

### Phase 9 — Ortak sözleşme testleri (fabrika)

- **Sorun:** Test hedefleri birbirini import edemez. #26'daki sözleşme `VademCoreTests` içindeydi, SwiftData testleri (`VademPersistenceTests`) onu kullanamazdı.
- **Çözüm:** `VademTestSupport` adlı normal bir hedef (sadece test hedefleri bağımlı). İçinde `Fixture` ve `PaymentRepositoryContract.scenarios` (29 senaryo).
- **Tek satırla yeni uygulama:** Her test hedefi `@Test(arguments: factories, PaymentRepositoryContract.scenarios)` ile tüm sözleşmeyi koşar. Swift Testing iki argüman listesinin kartezyen çarpımını alır: "uygulama × senaryo".
- **Swift 6 detayı:** Senaryolar `@MainActor` bir enum içinde; `@Test(arguments:)` listeyi actor dışından okuduğu için liste `nonisolated` olmalı.
- **Aleti ölçtük:** Bellek içi uygulamanın sıralamasını bilerek bozunca 29 senaryodan 6'sı kırmızıya döndü. Taşıma sırasında sözleşme gücünü kaybetmedi.

### Koşu #30 — SwiftData deposu (`SwiftDataPaymentRepository`)

- **Ne yapıldı:** `VademPersistence`'a `VademSchemaV1` (`1.0.0`, üç düz `@Model` kayıt, ilişki yok; kalemler `cardID` tutar), `VademMigrationPlan` ve `SwiftDataPaymentRepository` eklendi. Tutar `Double` değil tam ondalık metin olarak, ay yıl + ay sayısı olarak saklanıyor; bozuk kayıt okunurken çökmez, hata fırlatır (PR #31).
- **Sözleşme ilk denemede geçti:** 29 ortak senaryonun hepsi SwiftData'da ilk koşuda yeşildi. Sebep önceki iki adım: sözleşme #26'da (sıralama API'si adıyla, eşitlikte `id`) netleştirildi, sonra ortak `VademTestSupport` hedefine taşındı. İkinci uygulama, kuralı tahmin etmek yerine aynı testlerden geçti.
- **Review kapısı:** Bozuk kart ve taksit kayıtları test ediliyordu, bozuk abonelik kaydı (bilinmeyen periyot, yarım girilmiş son ay, 13. ay, okunamayan tutar) edilmiyordu; 13 bozuk durum eklendi, hepsi hata fırlatıyor. Açık bırakılan nit: sıralama yardımcısı bellek içi depodan kopyalandı (sapmayı zaten ortak sözleşme yakalar). `.appGroup` yolu paket testlerinde koşmuyor (entitlement yok); Phase 10'da uygulama açtığında gerçekten çalışacak.
- **Metrikler:** ~15 dk, 7 verify koşusu (0 kırmızı), 1 düzeltme turu; review 0 blocker / 0 major / 1 minor / 2 nit, UI check atlandı (ekran yok).
- **Ders:** Sözleşme testleri yalnızca ortak davranışı sınar; depolamaya özgü riskler (bozuk veri, yeniden açma, tam yuvarlama) uygulamanın kendi testlerinde kalmalı. Review'in bulduğu eksik tam da bu sınırdaydı.

### Phase 10 — UI check harness güncellemesi (fabrika)

#33'te (design system) UI check ve reviewer, harness'ın uzun ve animasyonlu ekranlara hazır olmadığını gösterdi:
- **Sonsuz animasyon = bitmeyen denetim:** Kartlardaki sürekli mesh kayması uygulamayı hiç boşta bırakmıyor, `performAccessibilityAudit` zaman aşımına uğruyordu. Artık her yakalama `-ui-static-motion` ile açılıyor; uygulama bu bayrağı görünce sürekli animasyonları durdurmak zorunda (Reduce Motion ile aynı yol).
- **Bir hata, kalan her şeyi siliyordu:** Denetim `try` ile hata fırlatınca döngü kırılıyor, AX5 varyantı hiç yakalanmıyordu. Artık hata `[a11y] … audit did not complete` olarak raporlanıp devam ediliyor.
- **Uzun ekranlar:** Ekran görüntüsü sadece ilk görünen kısmı alıyordu; kartlar sayfanın altında kalmıştı. `sections: [.top, .scrolled(to:named:)]` ile bölüm bölüm yakalanıyor.
- **Açılış argümanları:** `capture(screen:launchArguments:…)` ile ekran doğrudan açılıyor; test yazarının "kapat-yeniden aç" geçici çözümüne gerek kalmadı.
- **Doğrulama:** Geçici bir test ile iki bölüm (6 görüntü) ve bilerek bulunamayan bir bölüm denendi; hata her varyant için raporlandı, döngü durmadı.

### Phase 10 — Harness ikinci tur (fabrika)

#33'ün 2. turunda UI check, ilk harness düzeltmesinin de yetmediğini gösterdi:
- **"Görünür" ≠ "doğru yerde":** `scrolled(to:)` işaret görünür olunca duruyordu; tek kaydırma üç başlığı birden görünür yapınca üç bölüm aynı görüntüyü verdi (md5 aynı). Artık işaret ekranın üst %15'ine sürükleniyor.
- **Denetim kaydırma bitmeden başlıyordu:** Koyu modda kaydırılmış bölümlerde denetim zaman aşımına uğruyordu; muhtemelen kaydırma göstergesinin sönme animasyonu. Artık iki ardışık görüntü aynı olana kadar (en fazla ~3 sn) bekleniyor.
- **Yanlış örnek nokta:** Açık/koyu kontrolü ekran ortasından tek piksel alıyordu; büyük yazıda içerik denk geliyordu. Artık sol 4 pt kenar boşluğundan 5 pikselin medyanı.
- **Doğrulama:** #33'ün geçici bir kopyasında: 6 bölümün hepsi farklı görüntü, zaman aşımı yok, yanlış alarm yok. Bonus: denetim artık daha fazla gerçek sorun görüyor (AX5'te kart üstünde kontrast, koyu modda bir etiket). Daha iyi alet → daha çok gerçek bulgu.

### Koşu #33 — Design system ("Ink and Vade")

- **Ne yapıldı:** `VademFeatures`'a 13 renk token'ı (açık/koyu), altı mesh kart stili (`CardStyle`, UUID baytlarından FNV-1a ile; `hashValue` her açılışta değişir), `CardFaceView`, `AmountText`, `DueChip`, cam modifier'ı ve `-ui-gallery` ile açılan galeri eklendi. İlk görsel ekran ve ilk UI işi (PR #38).
- **Alet ürünle birlikte olgunlaştı:** UI check ilk turda ürünü değil harness'ı yakaladı (bitmeyen denetim, AX5'in hiç yakalanmaması, sadece ilk ekran). Koşu iki kez durdu, harness ayrı PR'larda düzeltildi (#34, #35), sonra ürün devam etti. Fabrika ayrımı kuralı işledi: hiçbiri issue branch'ine girmedi.
- **Daha iyi alet → daha çok gerçek bulgu:** Harness düzelince denetim, eskiden göremediği ürün sorunlarını gördü: VoiceOver tutarlarda `₺` sembolünü okuyordu (`spokenLabel` ile "Türk lirası"), `₺1.000.000,00` AX5'te sayının ortasından kırılıyordu, kart yazısının kontrastı AX5'te ve dört stilde yetmiyordu. Birim testi her mesh rengini beyaza karşı geçiriyordu; denetim ise ekrandaki gerçek bileşimi ölçüyor. Ders: ilk görsel ekranda alet de ilk kez gerçek yük altındaydı; aleti ve ürünü aynı koşuda olgunlaştırmak pahalı ama kaçınılmaz.
- **Sınırlı döngü işe yaradı:** Review limiti 2 tur; 3. tur kullanıcı onayıyla istisna oldu. 3. turdan sonra sonsuz düzeltme yerine durduk: ürün kalanları (kart yazısı kontrastı, navigasyon çubuğu) #36'ya, harness kalanları (kaydırma güvenilirliği, yarı gizli öğe gürültüsü, ~10 dk süre) #37'ye ayrıldı. PR, kriterlerin hepsi karşılanmadan açıkça yazılarak merge edildi; karar insanda kaldı.
- **Metrikler:** ~131 dk (iki fabrika PR'ı dahil), 12 verify koşusu (0 kırmızı), 3 düzeltme turu; review 0 blocker / 2 major / 3 minor / 5 nit, UI check 1 blocker / 9 major / 4 minor / 2 nit.

### Phase 10 — Hafif UI yakalama (fabrika)

#33'ün 3. turundaki harness kalanları (#37) ve #36'da bir UI check koşusunun kotanın belirgin bir kısmını harcaması üzerine (PR #41):
- **UI check agent'ı kapatıldı:** `/ship` adım 4'te orkestratör `UI_CHECK_ONLY=<ekranlar> scripts/ui-check.sh`'i reviewer çalışırken arka planda başlatıyor, sadece özet satırlarını okuyor; ekran görüntüsünü yalnızca bir satır gerektirdiğinde, 600 px kopyadan açıyor. Bekleme agent'ın işi değil. Test writer ve reviewer `sonnet` ile çalışıyor.
- **Ulaşılamayan bölümün kök nedeni:** Kaydırma hedefi büyük başlığın altına denk geliyordu; işaret orada dokunulabilir sayılmadığı için `chips` bölümüne ulaşılamıyordu. Hedef artık hep navigasyon çubuğunun altında; %5 tolerans yerine bir bant kullanılıyor, sürüklemeler salınmıyor (her sürükleme ~3 sn).
- **Gürültü ile hata ayrıldı:** Tam görünmeyen öğelerdeki denetim bulguları `[a11y-hidden]`, art arda aynı bölümler `[ui-note]` notu (`notes.txt`); hata sayılmıyorlar. Ulaşılamayan işaret, çerçeve, çubuk alt sınırı ve deneme sayısıyla raporlanıyor.
- **Süre:** Tam galeri yakalaması ~10 dk'dan 237 sn'ye indi (30 bölümün 30'u ulaşıldı, 30 görüntü). Bir koşuda XCTest "Find the Target Application" adımında 17 dk takıldığı için test başına 180 sn sınır kondu.
- **Ders:** Bir kapının maliyeti de kalitesinin parçası. Deterministik kısım (denetim, script) her zaman koşar; pahalı kısım (görüntüye bakmak) sadece bir sinyal gerektirdiğinde devreye girer.

### Koşu #42 — Aylık program (`MonthlySchedule`, ADR-0002)

- **Ne yapıldı:** "Bu ay ne ödenir?" kuralı önce ADR-0002'de (vade tarihine göre gruplama) kararlaştırıldı, sonra `MonthlySchedule` ve tablo testleri yazıldı. Ekstre günü / vade günü ay sınırlarını aşabildiği için bir kalem aynı gün iki kez vadeli olabiliyor; sıralamaya taksit numarası bu yüzden eklendi.
- **Kapılar:** Verify 7 koşu, 0 kırmızı. Reviewer 1. turda 0 blocker / 0 major / 2 minor / 4 nit buldu; hepsi test tarafındaydı (parayı `Double` literal ile yazan `combined()`, hiçbir şey doğrulamayan `extremes()`, iki yorum uyuşmazlığı, yıllık abonelik testi eksikliği). Kod ilk turda onaylandı.
- **Metrikler:** 9 dk, 1 düzeltme turu. İlk "hafif" koşu: UI agent'ı yok, test writer ve reviewer `sonnet`; alan saf domain olduğu için UI yakalama atlandı.
- **Ders:** Kural ADR'de yazıldığında reviewer beklenen değerleri koddan değil karardan yeniden hesaplayabiliyor; hata kodda değil testte çıktı.

### Mülakat sorusu: Bir iş kuralını neden kodda değil önce bir ADR'de kararlaştırırsın, ADR'ye neyi yazarsın?

**Cevap:**
- **Kod "ne"yi gösterir, "neden"i göstermez:** ADR olmazsa biri kodu "basitleştirip" kuralı sessizce bozar.
- **İş kuralı bir ürün kararıdır:** "Bu ay" tanımı gibi bir kural kullanıcının gördüğü toplamı değiştirir; yazılı olarak onaylanmalı.
- **ADR → kabul kriteri → tablo testi:** Test writer koddan değil kuraldan test yazar.
- **İçerik:** bağlam, tek cümlelik karar, sınır durumları (ekstre gününe düşen çekim, ay sonu, yıl dönümü), reddedilen seçenekler ve nedenleri, sonuçlar.
- **Değiştirilmez:** ADR (Architecture Decision Record) numaralanır; karar değişirse eskisini "yerini aldı" diye işaretleyen yeni bir ADR yazılır.
- **Ders:** Basit görünen kuralın çok yorumu vardır; yazılı karar yorum farkını koddan önce ortaya çıkarır.

### Mülakat sorusu: Test writer'ın bazı testleri ilk koşuda kırmızı yanınca beklenen değerleri düzelttiğini söylemesi neden bir risk, pipeline bunu nasıl yakalıyor?

**Cevap:**
- **Kırmızı test iki şey demektir:** ya beklenti yanlış ya kod. Beklentiyi koda uydurmak testi kodun aynası yapar; kodda hata varsa test onu onaylar (test oracle problemi).
- **Savunma 1:** Test writer koderin raporunu görmez; beklentiyi kabul kriterlerinden elle hesaplar.
- **Savunma 2:** Orkestratör bu itirafı reviewer'a özel olarak iletir; reviewer beklenen değerleri ADR'den bağımsız olarak yeniden hesaplar (#42'de hepsi doğru çıktı).
- **Savunma 3:** Verify kararı agent'ta değil script'te.
- **Kalan risk:** Reviewer da aynı yanlış yorumu yaparsa; bu yüzden ADR'de sınır durumları açıkça yazılır.
- **Ders:** "Test düzeltildi" cümlesi, "neye göre düzeltildi?" sorusunu gerektirir.

### Koşu #50 — Home: gelecek aylar şeridi

- **Ne yapıldı:** `UpcomingMonths` (VademCore, saf), `HomeViewModel.upcoming` / `select(month:)` ve yatay ay şeridi. Boş aylar sıfırla gösteriliyor; son desteklenen ayda sınırlanıyor.
- **Kapılar:** Verify 3 koşu, 0 kırmızı; reviewer 1. turda onayladı (0 blocker / 0 major / 3 minor / 1 nit), UI capture (`UI_CHECK_ONLY=home`) 0 a11y bulgusu. Düzeltme turu olmadı.
- **Metrikler:** 10 dk, 0 düzeltme turu. Önceki UI koşusunda (#45) kapıların yakaladığı kontrast ve test eksikleri bu kez çıkmadı.
- **Açık nokta:** VoiceOver "Türk lirası" okuyor, issue örneğindeki "₺" değil; ödeme satırlarıyla tutarlı olduğu için kabul edildi. `.isSelected` özelliği için otomatik doğrulama yok, sadece model bayrağı testli.
- **Ders:** `home-upcoming` ile `home` aynı görüntü çıktı (şerit zaten en üstte); `[ui-note]` mekanizması bunu hata saymadan gösterdi. Bu, gürültü/hata ayrımının (#37) işe yaradığını gösteriyor.

### Koşu #53 — Home: aylık takvim

- **Ne yapıldı:** `MonthlySchedule`'a güne göre gruplama (`days`, `entries(onDay:)`, `total(onDay:)`), `YearMonth.weekdayOfFirstDay`, `HomeViewModel`'de gün seçimi ve filtre, `HomeView`'da ay ızgarası (PR #55).
- **Kapılar:** Verify 6 koşu, 0 kırmızı. Reviewer 1. turda 0 blocker / 0 major / 2 minor / 2 nit buldu: `cell.day!` zorla açma ve yıl <= 0 için `weekdayOfFirstDay` kalanı; ikisi de düzeltildi (1 düzeltme turu).
- **UI check FAIL kaldı:** `UI_CHECK_ONLY=home` 2 major kontrast bulgusu verdi (7 a11y sorunu: `Fri`, `Mon` ve öğesiz `screen` kayıtları). Muhtemel neden takvim satırlarının durum çubuğunun arkasına kaydırılması; doğrulanmadı. Öğesiz bulgular çerçeveyle sınıflanamıyor, bu yüzden harness takibi ayrı bir `phase-N/...` PR'ına kaldı. Sıfır yükseklikli `safeAreaInset` bulguyu gidermedi, kaldırılabilir.
- **Harness:** PR #54 çubuğu olmayan ekranlarda `barBottom` hesabını düzeltti; bu koşu rebase ile onu aldı. Fabrika ayrımı yine korundu.
- **Ders:** Kapı kırmızı kaldığında PR bunu açıkça yazıp ("open") merge edildi; karar insanda. Metrikler: 116 dk, 6 verify, 1 düzeltme turu.

### Koşu #59 — UI check kontrast gürültüsü

- **Ne yapıldı:** Harness PR'ı, agent yok. Kontrast bulguları `[a11y-contrast]` (ikinci ölçümde tekrarlandı) ve `[a11y-flaky]` (tekrarlanmadı) notu oldu; diğer audit türleri hâlâ hata. Token çiftleri için `TokenContrastTests` (11 çift, açık/koyu, ≥ 4.5:1) eklendi.
- **Ayrım:** 3'er koşu: `gallery` eski gürültü (#53'ten önce de 9-12 satır, her koşuda farklı); `home` #53'ten beri deterministik (5, 5, 5), takvimin durum çubuğunun altından geçmesi.
- **Kapılar:** Sadece yeniden denemek yetmedi (`gallery` hâlâ 8, 8, 7 hata, ~245 sn). Notlara çevirdikten sonra 0 hata. Gerçek kontrast sorununu `dueSoon` açık rengini `B8A06A` yapan commit'siz deneme yakaladı: `TokenContrastTests` kırıldı.
- **Ders:** Kararsız bir ölçümü kapı yapma; deterministik olan kısmı (token oranları) birim teste taşı, kararsız olanı not olarak tut. Metrikler: 118 dk, 2 verify, 0 düzeltme turu.

### Koşu #62 — Taksit ekleme formu

- **Ne yapıldı:** `InstallmentDraft` (VademCore, saf doğrulama: başlık, kart, tutar, 1–36 taksit, ilk ay), `AddInstallmentViewModel` ve `AddInstallmentView` sheet'i, Home'da "+" butonu; kayıt `PaymentRepository` üzerinden, iki yeni `PaymentRepositoryContract` senaryosu (PR #63).
- **UI capture yakaladı:** İlk turda 28 adet `Text clipped` ve "Dynamic Type partially unsupported" (2 major). Sistem `Menu`/`Picker` etiketleri kırpılıyordu; kart ve ay seçimi özel satır + liste ekranına (`OptionList`) çevrildi. Sonraki tur a11y bulgusu yok.
- **Reviewer yakaladı:** `parseAmount` sınırsız hane/NaN (minor), 2. turda yeni `OptionList` ekranları için capture testi yok (major) ve sınırsız kesir hanesi. Hepsi düzeltildi; 3 düzeltme turu, 12 verify (1 kırmızı), 90 dk.
- **Açık noktalar:** Kart ekleme yok, taze depoda Kaydet kapalı kalır. `UI_CHECK_ONLY` adı `testFooScreen` kalıbına bağlı, yeni capture testleri sadece tam script ile koşuyor (harness için ayrı PR adayı).
- **Ders:** Sistem kontrolü her zaman erişilebilir değildir; audit kırılınca bileşeni değiştirmek, audit'i gevşetmekten doğru yol. Yeni ekranın (liste) kendi capture testi olmazsa kapı onu görmez.
