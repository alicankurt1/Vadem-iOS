# Öğrenme Notları

Her fazda öğrenilen kavramlar ve mülakat soruları.

## Phase 0 — Foundation

- **Yerel Swift Package ile modülerlik:** İş kuralları (`VademCore`) UI'dan ayrı bir modülde. Modül sınırı, bağımlılık yönünü derleyiciye zorlatır: Core, SwiftUI'yi göremez.
- **`swift test` ile simülatörsüz test:** Package macOS'u da desteklediği için domain testleri saniyeler içinde koşar.
- **xcconfig:** Build ayarları metin dosyasında, diff'lenebilir. Team ID gibi kişisel değerler git-ignore'lu `Local.xcconfig`'te.
- **Default actor isolation kapalı:** Xcode 26 yeni projelerde her şeyi varsayılan olarak `@MainActor` yapıyor; biz kapatıp izolasyonu açıkça yazıyoruz.
