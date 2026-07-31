# Çok Amaçlı Klasör Yönetim Aracı

Windows için, ağ paylaşımı kurulumunu (tarayıcı/fotokopi klasörü ve çok kullanıcılı "Ortak Havuz") grafik arayüzden tek tıkla yapan PowerShell aracı.

**Hazırlayan:** Mehmet IŞIK · **Sürüm:** v2.6 · 30.07.2026

## Özellikler

- **Tarama Klasörü** – `C:\Tarama` oluşturur, gizli paylaşım (`Tarama$`) olarak açar; eski cihazlar için SMB 1.0 aç/kapat seçeneği.
- **Ortak Klasör (Ana PC)** – `C:\OrtakHavuz` oluşturur, sınırlı yetkili `OrtakErisim` kullanıcısı açar, güçlü şifre zorunluluğu uygular, şifreyi panoya kopyalar ve masaüstüne kaydeder.
- **Diğer PC'den Bağlan** – İstemcide `cmdkey` ile şifre sormadan açılan bağlantı kısayolu oluşturur.
- **Kurulumu Kaldır** – Paylaşımları, kullanıcı hesabını, kısayolları temizler; güç ve güvenlik duvarı ayarlarını eski haline döndürür.
- **Durum Günlüğü** – Tüm işlemler zaman damgalı olarak izlenir.

## v2.6 Güvenlik İyileştirmeleri

- Komut enjeksiyonuna karşı `cmdkey.exe` doğrudan çağrılıyor.
- ACL kontrolü tam eşleşme (`-eq`) ile yapılıyor.
- Durum klasörü artık yönetici kontrolünden sonra oluşturuluyor.

## Gereksinimler

Windows + PowerShell 5.1 uyumlu + Yönetici yetkisi (otomatik UAC yükseltme ister).

## Kullanım

1. Scripti indirin, sağ tık → **PowerShell ile Çalıştır**.
2. UAC isteğini onaylayın.
3. İlgili sekmeden kurulum/bağlantı/kaldırma işlemini yapın.

```powershell
iwr "https://raw.githubusercontent.com/mhmtsk44/Klasor-Yonetim-Araci/refs/heads/main/Klasor_Yonetim_Araci.ps1" -OutFile "$env:TEMP\Klasor_Yonetim_Araci.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\Klasor_Yonetim_Araci.ps1"
```

> ⚠️ Sistem düzeyinde değişiklikler yapar (kullanıcı hesabı, güvenlik duvarı, ağ paylaşımı). Kaynağı doğrulamadan çalıştırmayın.

## Değiştirdiği Ayarlar

| Alan | Etki |
|---|---|
| Klasör | `C:\Tarama`, `C:\OrtakHavuz` |
| Paylaşım | `Tarama$`, `OrtakHavuz` (SMB) |
| Kullanıcı | `OrtakErisim` (sınırlı yetkili) |
| Güvenlik duvarı | Dosya/Yazıcı Paylaşımı, Ağ Bulma açılır (kaldırmada geri alınır) |
| Güç ayarı | Uyku/hazırda bekletme kapatılır (kaldırmada geri alınır) |

Yedekler `C:\ProgramData\KlasorYonetimAraci` altında tutulur.

## Not

`Ortak_Klasor_Baglanti_Bilgileri.txt` şifreyi düz metin içerir; iletim sonrası silinmesi önerilir. SMB 1.0 yalnızca zorunluysa açılmalıdır.

## Lisans

Serbestçe kullanılabilir, değiştirilebilir ve dağıtılabilir. Kaynak belirtmek zorunlu değil, takdir edilir.
