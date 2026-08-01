# 📁 Çok Amaçlı Klasör Yönetim Aracı

> **v3.2.2** — Yazıcı/fotokopi cihazınızın tarayabileceği bir klasör ve bilgisayarlar arası ortak dosya paylaşımı kurmanızı sağlayan, buton tabanlı bir Windows programı. Teknik bilgi gerekmez.

<p align="center">
  <a href="https://mhmtsk44.github.io/Klasor-Yonetim-Araci/">
    <img src="https://img.shields.io/badge/Canlı%20Arayüz-Önizleme-0d6efd?style=for-the-badge" alt="Canlı Önizleme">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white" alt="PowerShell">
  <img src="https://img.shields.io/badge/dil-T%C3%BCrk%C3%A7e-red" alt="Dil">
  <img src="https://img.shields.io/badge/bakım-aktif-brightgreen" alt="Bakım">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/lisans-MIT-yellow" alt="Lisans"></a>
</p>

<p align="center">
  <b><a href="https://mhmtsk44.github.io/Klasor-Yonetim-Araci/">🔗 Canlı, tıklanabilir arayüz önizlemesini aç</a></b>
  <br>
  <sub>Arayüz tasarımını doğrudan tarayıcınızda test edebilirsiniz.</sub>
</p>

---

## Gereksinimler

- Windows 10, 11 veya Server
- Yönetici yetkisi (program otomatik ister)

## Kurulum

1. Başlat menüsüne `PowerShell` yazın.
2. Sağ tıklayıp **Yönetici olarak çalıştır**'ı seçin.
3. Şu komutu yapıştırıp Enter'a basın:

```powershell
irm "https://raw.githubusercontent.com/mhmtsk44/Klasor-Yonetim-Araci/refs/heads/main/Klasor_Yonetim_Araci.ps1" | iex
```

---

## ✨ Özellikler

### 📂 Tarama Klasörü
- Yazıcı/fotokopi cihazlarının tarayabileceği gizli (`Tarama$`) paylaşımı tek tıkla kurar.
- Gerekli güvenlik duvarı kurallarını otomatik açar.
- Klasör izinlerini (NTFS ve paylaşım) ayarlar.
- Tarama yarıda kesilmesin diye uyku modunu geçici kapatır.
- Yazıcıya gireceğiniz bilgileri masaüstünüze `.txt` olarak kaydeder.

### 🗂️ Ortak Klasör (Ana PC)
- Sadece paylaşım için kullanılan, sınırlı yetkili **OrtakErişim** kullanıcı hesabı oluşturur.
- `C:\OrtakHavuz` paylaşımını güvenli şekilde kurar.
- Bağlantı bilgilerini panoya kopyalar ve masaüstüne `.txt` olarak kaydeder.

### 🌐 Diğer PC'den Bağlan
- Ortak klasörü kuran bilgisayara güvenli şekilde bağlanır.
- Kimlik bilgilerini Windows Kimlik Bilgisi Yöneticisi'ne kaydeder.
- Bir daha şifre sormadan paylaşımı kullanmaya devam edersiniz.

### 🧹 Kurulumu Kaldır
- Tarama klasörünü, ortak klasörü veya ikisini birden kaldırabilirsiniz.
- Oluşturulan kullanıcı hesabını siler.
- Paylaşımları ve masaüstü kısayollarını temizler.
- İki kurulum da kaldırıldığında güvenlik duvarı ve güç ayarlarını otomatik eski haline getirir.

### 📝 Kalıcı Loglama
Tüm işlemler hem programın kendi ekranındaki günlük kutusuna hem de aşağıdaki dosyaya yazılır:

```text
%ProgramData%\KlasorYonetim\Program.log
```

---

## 🧭 Sekmeler — Özet

| Sekme | Ne yapar |
|---|---|
| 📂 Tarama Klasörü | Yazıcının tarayıp kaydedebileceği bir paylaşım kurar. |
| 🗂️ Ortak Klasör (Ana PC) | Diğer bilgisayarların bağlanabileceği ortak paylaşım klasörünü kurar. |
| 🌐 Diğer PC'den Bağlan | Ortak klasöre başka bir bilgisayardan bağlanmanızı sağlar. |
| 🧹 Kurulumu Kaldır | Kurulan bileşenleri, ayarlarla birlikte kaldırır. |

---

## ⚠️ Güvenlik Notları

- Kurulum sırasında oluşturulan parola, istenirse masaüstüne düz metin `.txt` dosyası olarak kaydedilebilir.
  - Kurulum tamamlandıktan sonra bu dosyanın silinmesi önerilir.
- **Tarama Klasörü** paylaşımı, bazı tarayıcı cihazlarının çalışabilmesi için **Everyone** (herkes) grubuna açıktır.
  - Yalnızca güvenilir yerel ağlarda kullanılması tavsiye edilir.
- SMB 1.0 yalnızca eski cihazlar için gereklidir.
  - İhtiyaç kalmadığında kapatılması önerilir.
- Kaldırma işlemleri geri alınamaz.

## Lisans

MIT Lisansı — serbestçe kullanılabilir, değiştirilebilir ve dağıtılabilir.

---

<p align="center">Hazırlayan: <b>Mehmet IŞIK</b></p>
