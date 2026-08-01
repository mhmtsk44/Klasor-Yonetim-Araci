# 📁 Çok Amaçlı Klasör Yönetim Aracı

**v3.2.2** — Windows ağlarında tarama klasörü ve ortak paylaşım altyapısını tek bir arayüzden kurup yöneten PowerShell (WinForms) aracı.

<p align="center">
  <a href="https://mhmtsk44.github.io/Klasor-Yonetim-Araci/" target="_blank" rel="noopener noreferrer"><b>🔗 Canlı, tıklanabilir arayüz önizlemesini aç</b></a>
  <br>
  <sub>Arayüz tasarımını, kurumsal renk paletini ve buton tepkilerini doğrudan tarayıcınızda test edebilirsiniz.</sub>
</p>

---

## ✨ Özellikler

- **Tarama Klasörü** — Ağdaki yazıcı/fotokopi makinelerinin tarayabileceği, gizli (`Tarama$`) bir SMB paylaşımını tek tıkla kurar. Gerekli güvenlik duvarı kurallarını, ACL izinlerini ve uyku modu ayarlarını otomatik yapılandırır.
- **Ortak Klasör (Host)** — Ayrı, sınırlı yetkili bir `OrtakErisim` kullanıcı hesabıyla güvenli bir dosya paylaşım havuzu (`C:\OrtakHavuz`) oluşturur.
- **Diğer PC'den Bağlan** — Ağdaki host bilgisayara, kimlik bilgilerini Windows Kimlik Bilgisi Yöneticisi'ne kaydederek güvenli şekilde bağlanır.
- **Kurulumu Kaldır** — Seçmeli veya tam temizlik: paylaşımları, hesabı, masaüstü kısayollarını ve değiştirilen sistem ayarlarını (güç profili, güvenlik duvarı kuralları) orijinal haline geri döndürür.
- **Kriptografik Şifre Üretici** — `System.Security.Cryptography.RandomNumberGenerator` ve Fisher-Yates karıştırma ile güçlü, tahmin edilemez şifreler üretir.
- **Modern Arayüz ve Uyum** — "Segoe UI Emoji" fontu ve UTF-8 (BOM) kodlaması ile Windows 10/11 üzerinde tam renkli, sorunsuz emoji/simge gösterimi sunar. Eski JIT çizim hatalarından (`op_Subtraction`) arındırılmıştır.
- **Kalıcı Loglama** — Tüm işlemler zaman damgalı olarak hem uygulama içi konsolda hem de `%ProgramData%\KlasorYonetim\Program.log` dosyasında tutulur.
- **Otomatik Yönetici Yükseltme** — Tek dosyalık, bağımlılıksız `.ps1` betiği, yönetici yetkisi eksikse kendini otomatik olarak yeniden başlatır.

## 🖥️ Gereksinimler

- Windows 10/11 veya Windows Server (SMB ve `NetSecurity` modüllerinin bulunduğu bir sürüm)
- PowerShell 5.1 veya üzeri
- Yönetici yetkisi

## 🚀 Kullanım

Betiği bilgisayarınıza manuel olarak indirmekle uğraşmadan, doğrudan PowerShell üzerinden aşağıdaki komutları çalıştırarak anında kullanabilirsiniz:

```powershell
iwr "https://raw.githubusercontent.com/mhmtsk44/Klasor-Yonetim-Araci/refs/heads/main/Klasor_Yonetim_Araci_v3.2.2.ps1" -OutFile "$env:TEMP\Klasor_Yonetim_Araci_v3.2.2.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\Klasor_Yonetim_Araci_v3.2.2.ps1"
```

*(Alternatif olarak `.ps1` dosyasını bilgisayarınıza indirip, sağ tıklayarak **"PowerShell ile Çalıştır"** diyebilirsiniz.)*

## 🧭 Sekmeler

| Sekme | Amaç |
|---|---|
| **1. Tarama Klasörü** | Yazıcı/fotokopi tarama altyapısını kurar, gerekirse eski SMB 1.0 protokolünü açıp kapatır. |
| **2. Ortak Klasör (Ana PC)** | Ağ ortak paylaşım hesabını ve klasörünü oluşturur, bağlantı bilgilerini panoya kopyalar. |
| **3. Diğer PC'den Bağlan** | Bu bilgisayarı, ağdaki host'a istemci olarak bağlar. |
| **4. Kurulumu Kaldır** | Seçmeli veya tam temizlik yapar, sistemi orijinal haline döndürür. |

## ⚠️ Güvenlik Notları

- Ortak Havuz kurulumu sırasında oluşturulan şifre, kullanıcının onayıyla masaüstüne düz metin `.txt` dosyası olarak kaydedilebilir — kurulumdan sonra bu dosyayı güvenliğiniz için silmeniz önerilir.
- "Tarama Klasörü" paylaşımı, ağ tarayıcılarının kimlik doğrulamasız erişebilmesi için `Everyone` grubuna açıktır; yalnızca güvenilir yerel ağlarda kullanın.
- SMB 1.0'ı yalnızca gerçekten ihtiyacınız olan eski bir cihaz varsa geçici olarak açın.

## 📄 Lisans

Bu proje olduğu gibi (as-is) sunulmuştur. Serbestçe kullanılabilir, değiştirilebilir ve dağıtılabilir. Kullanım sorumluluğu kullanıcıya aittir.

---

<p align="center"><sub>Hazırlayan: <b>Mehmet IŞIK</b></sub></p>
