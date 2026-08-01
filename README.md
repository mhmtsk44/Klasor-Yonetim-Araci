# 📁 Çok Amaçlı Klasör Yönetim Aracı

**v3.2.2** — Windows ağlarında tarama klasörü ve ortak paylaşım altyapısını tek bir arayüzden kurup yöneten PowerShell (WinForms) aracı.

<p align="center">
  <img src="assets/onizleme.png" alt="Klasör Yönetim Aracı arayüz önizlemesi" width="820">
</p>

<p align="center">
  <a href="https://KULLANICI_ADI.github.io/REPO_ADI/"><b>🔗 Canlı, tıklanabilir önizlemeyi aç</b></a>
  &nbsp;•&nbsp;
  <sub>Yukarıdaki görsel statiktir; sekmelere gerçekten tıklamak için canlı önizlemeyi kullanın.</sub>
</p>

> **Not:** Canlı önizleme bağlantısı GitHub Pages ile yayınlanır. Kendi deponuzda yayına almak için aşağıdaki [GitHub Pages ile Canlı Önizleme](#-github-pages-ile-canlı-önizleme) bölümüne bakın ve yukarıdaki linkteki `KULLANICI_ADI`/`REPO_ADI` kısımlarını kendi bilgilerinizle değiştirin.

---

## ✨ Özellikler

- **Tarama Klasörü** — Ağdaki yazıcı/fotokopi makinelerinin tarayabileceği, gizli (`Tarama$`) bir SMB paylaşımını tek tıkla kurar. Gerekli güvenlik duvarı kurallarını, ACL izinlerini ve uyku modu ayarlarını otomatik yapılandırır.
- **Ortak Klasör (Host)** — Ayrı, sınırlı yetkili bir `OrtakErisim` kullanıcı hesabıyla güvenli bir dosya paylaşım havuzu (`C:\OrtakHavuz`) oluşturur.
- **Diğer PC'den Bağlan** — Ağdaki host bilgisayara, kimlik bilgilerini Windows Kimlik Bilgisi Yöneticisi'ne kaydederek güvenli şekilde bağlanır.
- **Kurulumu Kaldır** — Seçmeli veya tam temizlik: paylaşımları, hesabı, masaüstü kısayollarını ve değiştirilen sistem ayarlarını (güç profili, güvenlik duvarı kuralları) orijinal haline geri döndürür.
- **Kriptografik şifre üretici** — `System.Security.Cryptography.RandomNumberGenerator` ve Fisher-Yates karıştırma ile güçlü, tahmin edilemez şifreler üretir.
- **Modern Arayüz ve Uyum** — "Segoe UI Emoji" fontu ve UTF-8 (BOM) kodlaması ile Windows 10/11 üzerinde tam renkli, sorunsuz emoji/simge gösterimi sunar. Eski JIT çizim hatalarından (op_Subtraction) arındırılmıştır.
- **Kalıcı loglama** — Tüm işlemler zaman damgalı olarak hem uygulama içi konsolda hem de `%ProgramData%\KlasorYonetim\Program.log` dosyasında tutulur.
- **Otomatik yönetici yükseltme, DPI koruması, ayar hatırlama** — Tek dosyalık, bağımlılıksız bir `.ps1` betiği.

## 🖥️ Gereksinimler

- Windows 10/11 veya Windows Server (SMB ve `NetSecurity` modüllerinin bulunduğu bir sürüm)
- PowerShell 5.1 veya üzeri
- Yönetici yetkisi (betik gerekirse kendini otomatik olarak yönetici olarak yeniden başlatır)

## 🚀 Kullanım

```powershell
# Depoyu klonlayın veya .ps1 dosyasını indirin, ardından:
powershell -ExecutionPolicy Bypass -File .\Klasor_Yonetim_Araci_v3.2.2.ps1
```

Betik yönetici yetkisiyle çalışmıyorsa otomatik olarak UAC istemi gösterip kendini yeniden başlatır.

## 🧭 Sekmeler

| Sekme | Amaç |
|---|---|
| **1. Tarama Klasörü** | Yazıcı/fotokopi tarama altyapısını kurar, gerekirse eski SMB 1.0 protokolünü açıp kapatır. |
| **2. Ortak Klasör (Ana PC)** | Ağ ortak paylaşım hesabını ve klasörünü oluşturur, bağlantı bilgilerini panoya kopyalar. |
| **3. Diğer PC'den Bağlan** | Bu bilgisayarı, ağdaki host'a istemci olarak bağlar. |
| **4. Kurulumu Kaldır** | Seçmeli veya tam temizlik yapar, sistemi orijinal haline döndürür. |

## ⚠️ Güvenlik Notları

- Ortak Havuz kurulumu sırasında oluşturulan şifre, kullanıcının onayıyla masaüstüne düz metin `.txt` dosyası olarak kaydedilebilir — bu dosyayı okuduktan sonra silmeniz önerilir.
- "Tarama Klasörü" paylaşımı, ağ tarayıcılarının kimlik doğrulamasız erişebilmesi için `Everyone` grubuna açıktır; yalnızca güvenilir yerel ağlarda kullanın.
- SMB 1.0'ı yalnızca gerçekten ihtiyacınız olan eski bir cihaz varsa açın; işiniz bitince kapatın.

## 🌐 GitHub Pages ile Canlı Önizleme

Bu depoda `docs/index.html` olarak hazır bir interaktif arayüz önizlemesi bulunuyor. Kendi deponuzda canlıya almak için:

1. GitHub'da deponuzu açın → **Settings** → sol menüden **Pages**.
2. **Build and deployment** altında **Source** olarak **Deploy from a branch** seçin.
3. **Branch** kısmından `main` (veya kullandığınız ana dal) ve klasör olarak **/docs**'u seçip **Save**'e basın.
4. Birkaç dakika içinde site şu adreste yayına girer:
   ```
   https://KULLANICI_ADI.github.io/REPO_ADI/
   ```
5. Bu README'nin en üstündeki bağlantıyı kendi kullanıcı adınız ve repo adınızla güncelleyin.

> Not: `docs/index.html` yalnızca bir **görsel önizlemedir** — tarayıcıda çalışır ama gerçek bir işlem yapmaz (klasör oluşturmaz, paylaşım kurmaz). Gerçek işlemler için `.ps1` dosyasını yönetici olarak yerel bilgisayarınızda çalıştırmanız gerekir; bunun teknik nedeni, tarayıcı güvenlik modelinin bir web sayfasının sisteminizde dosya/ağ/kullanıcı işlemleri yapmasına izin vermemesidir.

## 📄 Lisans

Bu proje olduğu gibi (as-is) sunulmuştur; kullanım sorumluluğu kullanıcıya aittir.

---

<p align="center"><sub>Hazırlayan: <b>Mehmet IŞIK</b></sub></p>
