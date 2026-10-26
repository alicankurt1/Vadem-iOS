# App Store listing

Everything that can be prepared in the repo for the App Store Connect listing. Account, signing, upload and submission are done by the owner by hand.

App Store limits used below: name ≤ 30, subtitle ≤ 30, promotional text ≤ 170, description ≤ 4000, keywords ≤ 100 characters (comma-separated, no spaces needed after commas). Character counts are given next to each text.

## Build and version

- Version (`MARKETING_VERSION`): `1.0`
- Build (`CURRENT_PROJECT_VERSION`): `1`
- Both are set only in `Config/Shared.xcconfig`; no target overrides them. Bump the build number there for every upload.
- Primary category: Finance. Secondary category: Productivity.
- Devices: iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), iOS 18 or later.
- Primary language: English (U.S.). Additional localization: Turkish.

## Name and subtitle

| Field | English (U.S.) | Turkish |
|---|---|---|
| Name | `Vadem` (5) | `Vadem` (5) |
| Subtitle | `Installments & subscriptions` (28) | `Taksit ve abonelik takibi` (25) |

If the name is taken, fall back to `Vadem: Monthly Payments` (23) / `Vadem: Aylık Ödemeler` (21).

## Promotional text

- English (114): `How much do you pay this month? Add your installments and subscriptions once and Vadem answers it, on your device.`
- Turkish (112): `Bu ay ne kadar ödüyorsun? Taksitlerini ve aboneliklerini bir kez gir, Vadem cevaplasın; veriler cihazında kalır.`

## Description

### English (U.S.)

```
How much do I pay this month? Vadem answers that one question.

Add your credit card installments and subscriptions once. Vadem works out what is due each month, which card it is on and when the last installment is paid.

YOUR MONTH AT A GLANCE
- See this month's total and how much of it is already due.
- Swipe through the next months to see what is coming.
- A calendar shows each day's total; tap a day to see its payments.

INSTALLMENTS AND SUBSCRIPTIONS
- Add installment plans with their amount, number of installments and first month.
- Add monthly or yearly subscriptions.
- Group everything by card, with a total per card.

CHARTS
- A bar chart of the next 12 months, split into installments and subscriptions.
- Pick a month to see it by card and find out when your last installment is paid.

REMINDERS, WIDGET AND SIRI
- Optional payment reminders, scheduled on your device.
- A Home Screen and Lock Screen widget with the month's total and the next payments.
- Ask Siri or Shortcuts for your monthly total or your next payment.

ASSISTANT
- On devices with Apple Intelligence, ask questions about your payments in your own words. Answers come from Apple's on-device model; nothing leaves your device.

PRIVATE BY DESIGN
- No account and no bank connection: you enter every value yourself.
- No analytics, no tracking, no ads.
- Your data stays on your device.

Available in English and Turkish.
```

### Turkish

```
Bu ay ne kadar ödüyorum? Vadem bu tek soruyu cevaplar.

Kredi kartı taksitlerini ve aboneliklerini bir kez gir. Vadem her ay ne ödeyeceğini, hangi karttan çıkacağını ve son taksitin ne zaman biteceğini hesaplar.

AYIN TEK BAKIŞTA
- Bu ayın toplamını ve ne kadarının vadesinin geldiğini gör.
- Sonraki aylara kaydırarak neler geleceğini incele.
- Takvim her günün toplamını gösterir; günün ödemelerini görmek için bir güne dokun.

TAKSİTLER VE ABONELİKLER
- Taksit planlarını tutarı, taksit sayısı ve ilk ayıyla ekle.
- Aylık veya yıllık abonelikleri ekle.
- Her şeyi kartlara göre, kart başına toplamla gör.

GRAFİKLER
- Önümüzdeki 12 ayın taksit ve abonelik olarak ayrılmış çubuk grafiği.
- Bir ay seçerek kartlara göre dağılımını ve son taksitinin ne zaman ödeneceğini gör.

HATIRLATMALAR, WIDGET VE SİRİ
- İsteğe bağlı, cihazında planlanan ödeme hatırlatmaları.
- Ayın toplamını ve sıradaki ödemeleri gösteren Ana Ekran ve Kilitli Ekran widget'ı.
- Aylık toplamını veya sıradaki ödemeni Siri'ye ya da Kestirmeler'e sor.

ASİSTAN
- Apple Intelligence destekleyen cihazlarda ödemelerinle ilgili soruları kendi cümlelerinle sor. Yanıtlar Apple'ın cihaz üzerindeki modelinden gelir; hiçbir şey cihazından çıkmaz.

GİZLİLİK ÖNCELİKLİ
- Hesap yok, banka bağlantısı yok: tüm değerleri sen girersin.
- Analiz yok, takip yok, reklam yok.
- Verilerin cihazında kalır.

Türkçe ve İngilizce olarak kullanılabilir.
```

Both descriptions are well under 4000 characters (about 1,400 English, 1,500 Turkish). Feature claims match the shipped app; the assistant needs iOS 26 and Apple Intelligence, so the text says "on devices with Apple Intelligence".

## Keywords

Words already in the name or subtitle are not repeated (App Store indexes those separately).

- English (90): `credit card,payment,monthly,budget,reminder,bill,expense,tracker,debt,due date,widget,plan`
- Turkish (89): `kredi kartı,ödeme,aylık,bütçe,hatırlatma,fatura,harcama,borç,ekstre,vade,kart,widget,plan`

## Screenshot plan

Images are not generated here; they are produced by hand or a script later. Use the in-memory sample data (`-ui-sample-data`) so no personal data appears, and static motion (`-ui-static-motion`) so the card meshes do not blur.

### Device sizes

| Display | Example device | Portrait pixels | Required |
|---|---|---|---|
| iPhone 6.9" | iPhone 17 Pro Max | 1320 × 2868 | Yes (scaled down for smaller iPhones) |
| iPhone 6.5" | iPhone 11 Pro Max | 1242 × 2688 | Only if 6.9" is not provided |
| iPad 13" | iPad Pro 13-inch (M4) | 2064 × 2752 | Yes (the app supports iPad) |

### Screens (in listing order)

1. Home, top: hero panel with the month's total and the amount already due.
2. Home, calendar: a day selected, the list filtered to that day.
3. Analytics: 12-month bar chart with a month selected (donut by card and the "last installment" insight).
4. Add installment form, filled in with a sample plan.
5. Add subscription form, filled in.
6. Assistant chat with one question and answer (iOS 26 device with Apple Intelligence; skip if not available).
7. Widget on the Home Screen (medium) and Lock Screen.
8. Settings: payment reminders on, timing picked.

### Appearances and languages

- English (U.S.) set: light appearance for screens 1–8, plus dark appearance for screens 1 and 3.
- Turkish set: the same screens with the device language set to Turkish (or the existing `…Turkish` UI capture launch arguments).
- Optional caption per screenshot (short headline above the device frame); keep the same order in both languages.

## Age rating

Answers for the App Store Connect age rating questionnaire. Expected result: **4+**.

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Prolonged graphic or sadistic realistic violence | None |
| Profanity or crude humor | None |
| Mature or suggestive themes | None |
| Horror or fear themes | None |
| Medical or treatment information | None |
| Alcohol, tobacco or drug use or references | None |
| Simulated gambling | None |
| Sexual content or nudity | None |
| Graphic sexual content and nudity | None |
| Contests | None |
| Gambling (real money) | No |
| Unrestricted web access | No |
| User-generated content shared with other users | No |
| Messaging or chat with other users | No (the assistant only answers about the user's own data, on device) |
| Advertising | No |
| Parental controls / age assurance | No |
| Made for Kids | No |

## App privacy (privacy nutrition label)

Matches `Vadem/PrivacyInfo.xcprivacy` (and the widget's manifest) and [`privacy.md`](privacy.md).

- **Data collection:** "No, we do not collect data from this app." (`NSPrivacyCollectedDataTypes` is empty.) Data entered by the user is stored only on the device and never sent to the developer or third parties, so it is not "collected" in App Store terms.
- **Tracking:** No (`NSPrivacyTracking = false`, no tracking domains).
- **Third-party SDKs:** none.
- **Required-reason APIs** (manifest only, not part of the label): `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1` (the app reads and writes its own settings).
- Resulting label: **Data Not Collected**.

## Export compliance

The app uses no encryption of its own and makes no network requests. Answer "None of the algorithms mentioned above" / no non-exempt encryption when App Store Connect asks.

## URLs and contact

| Field | Value |
|---|---|
| Support URL | `[support URL — owner to fill in]` |
| Marketing URL (optional) | `[marketing URL — owner to fill in]` |
| Privacy Policy URL | `[privacy policy URL — owner to fill in]` (publish the text of [`privacy.md`](privacy.md) there) |
| Contact email (review notes) | `[contact email — owner to fill in]` |
| Copyright | `[year and owner name — owner to fill in]` |

## Review notes

- No account or login is needed; reviewers can add a card and a payment from Home.
- The assistant appears only on iOS 26 devices with Apple Intelligence; on other devices it shows an explanation instead.
- The widget and Siri features need the App Group, which is configured in the app and widget entitlements.
