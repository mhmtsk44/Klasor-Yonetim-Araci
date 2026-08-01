# 📁 Çok Amaçlı Klasör Yönetim Aracı

> **v3.2.2** — Windows ağlarında tarama klasörü ve ortak paylaşım altyapısını tek bir arayüzden kurup yöneten PowerShell (WinForms) aracı.

<p align="center">
  <a href="https://mhmtsk44.github.io/Klasor-Yonetim-Araci/">
    <img src="https://img.shields.io/badge/Canlı%20Arayüz-Önizleme-0d6efd?style=for-the-badge" alt="Canlı Önizleme">
  </a>
</p>

<p align="center">
  <b>
    <a href="https://mhmtsk44.github.io/Klasor-Yonetim-Araci/">
      🔗 Canlı, tıklanabilir arayüz önizlemesini aç
    </a>
  </b>
  <br>
  <sub>Arayüz tasarımını, kurumsal renk paletini ve buton tepkilerini doğrudan tarayıcınızda test edebilirsiniz.</sub>
</p>

---

# ✨ Özellikler

### 📂 Tarama Klasörü
- Ağdaki yazıcı/fotokopi cihazlarının tarayabileceği gizli (`Tarama$`) SMB paylaşımını tek tıkla oluşturur.
- Güvenlik duvarı kurallarını otomatik yapılandırır.
- NTFS ve paylaşım izinlerini ayarlar.
- Güç profili ve uyku modu ayarlarını gerekli şekilde düzenler.

### 🗂️ Ortak Klasör (Host)
- Ayrı ve sınırlı yetkili **OrtakErisim** kullanıcı hesabı oluşturur.
- `C:\OrtakHavuz` paylaşımını güvenli şekilde kurar.
- Paylaşım bilgilerini kolayca kopyalayabilirsiniz.

### 🌐 Diğer PC'den Bağlan
- Ağdaki Host bilgisayara güvenli şekilde bağlanır.
- Kimlik bilgilerini Windows Kimlik Bilgisi Yöneticisi'ne kaydeder.
- Yeniden giriş gerektirmeden paylaşımı kullanabilirsiniz.

### 🧹 Kurulumu Kaldır
- Seçmeli veya tam kaldırma yapabilir.
- Oluşturulan kullanıcıyı kaldırır.
- Paylaşımları siler.
- Masaüstü kısayollarını temizler.
- Güvenlik duvarı ve güç ayarlarını eski haline getirir.

### 🔐 Güçlü Şifre Üretici
- `System.Security.Cryptography.RandomNumberGenerator`
- Fisher-Yates karıştırma algoritması
- Kriptografik olarak güvenli ve tahmin edilmesi zor şifre üretimi

### 🎨 Modern Arayüz
- Windows 10/11 uyumlu WinForms arayüzü
- **Segoe UI Emoji** desteği
- UTF-8 (BOM) kodlama
- Renkli emoji desteği
- Eski WinForms çizim hatalarından (`op_Subtraction`) arındırılmış yapı

### 📝 Kalıcı Loglama
Tüm işlemler hem uygulama içerisindeki konsola hem de aşağıdaki log dosyasına yazılır:

```text
%ProgramData%\KlasorYonetim\Program.log
```

### ⚡ Otomatik Yönetici Yetkisi
- Tek dosyalık PowerShell betiği
- Yönetici değilse kendini otomatik olarak Yönetici olarak yeniden başlatır.

---

# 🖥️ Gereksinimler

- Windows 10
- Windows 11
- Windows Server (SMB ve NetSecurity modülü bulunan sürümler)
- PowerShell 5.1 veya üzeri
- Yönetici Yetkisi

---

# 🚀 Kurulum

## Yönetici olarak PowerShell'i açın

Başlat menüsüne **PowerShell** yazın.

Ardından:

> Sağ tıklayın → **Yönetici olarak çalıştır**

Sonrasında aşağıdaki komutu çalıştırın.

```powershell
irm "https://raw.githubusercontent.com/mhmtsk44/Klasor-Yonetim-Araci/refs/heads/main/Klasor_Yonetim_Araci.ps1" | iex
```

---

# 🧭 Sekmeler

| Sekme | Açıklama |
|-------|----------|
| 📂 **1. Tarama Klasörü** | Yazıcı/Fotokopi tarama altyapısını kurar. Gerekirse SMB 1.0'ı açıp kapatabilir. |
| 🗂️ **2. Ortak Klasör (Ana PC)** | Ortak paylaşım hesabını ve klasörünü oluşturur. Bağlantı bilgilerini panoya kopyalar. |
| 🌐 **3. Diğer PC'den Bağlan** | İstemci bilgisayarı Host bilgisayara bağlar. |
| 🧹 **4. Kurulumu Kaldır** | Sistemi eski haline döndürür. |

---

# ⚠️ Güvenlik Notları

- Kurulum sırasında oluşturulan parola istenirse masaüstüne düz metin `.txt` dosyası olarak kaydedilebilir.
  - Kurulum tamamlandıktan sonra bu dosyanın silinmesi önerilir.

- **Tarama Klasörü** paylaşımı bazı tarayıcı cihazlarının çalışabilmesi için **Everyone** grubuna açıktır.
  - Yalnızca güvenilir yerel ağlarda kullanılması tavsiye edilir.

- SMB 1.0 yalnızca eski cihazlar için gereklidir.
  - İhtiyaç kalmadığında kapatılması önerilir.

---

# 📄 Lisans

Bu proje **MIT Lisansı** ile lisanslanmıştır.

İsteyen herkes;

- Kullanabilir
- Değiştirebilir
- Dağıtabilir
- Ticari projelerde kullanabilir

Yazılım **olduğu gibi (AS IS)** sunulmaktadır ve herhangi bir garanti verilmez.

---

<p align="center">
  <b>Hazırlayan</b><br>
  Mehmet IŞIK
</p>
