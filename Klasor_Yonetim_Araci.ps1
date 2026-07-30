<#
.SYNOPSIS
Çok Amaçlı Klasör Yönetim Aracı
Hazırlayan: Mehmet IŞIK
Güncelleme: 30.07.2026 - Hibrit Sürüm v2.6 (Güvenlik ve İzin İyileştirmeleri)

.DEĞİŞİKLİK NOTLARI
- [v2.6] Komut Enjeksiyonu Koruması: Şifrelerdeki metakarakterlerin (&, |, vb.) cmd.exe tarafından işletilmesini önlemek için cmdkey.exe doğrudan çağrıldı.
- [v2.6] ACL Tam Eşleşme: Substring (-match) kaynaklı yanlış izin okumalarını önlemek için kullanıcı adı doğrulamaları kesin eşleşmeye (-eq) çevrildi.
- [v2.6] Yetki Önceliği: StateDir oluşturma adımı Test-Admin kontrolünden sonraya taşınarak yetkisiz çalıştırmalardaki gizli hatalar giderildi.
- Sağ tıkla çalıştırıldığında kapanma sorunu çözüldü (Boşluklu dizinler için yol koruması eklendi).
- "#Requires -RunAsAdministrator" kısıtlaması kaldırılarak "PowerShell ile Çalıştır" işlevi uyumlu hale getirildi.
- PS 5.1 uyumluluğu için JSON dönüştürmelerinde "-AsHashtable" kaldırıldı.
- OrtakHavuz bağlantısı (İstemci) artık "Z:" sürücüsü haritalamak yerine Windows Kimlik Bilgisi Yöneticisine (Credential Manager) kaydediliyor.
- Çift şifre sorma sorununu önlemek için istemci bağlantısında kullanıcı adı "$hostName\OrtakErisim" olarak tanımlandı ve ağ senkronizasyonu için 1 sn gecikme eklendi.
- Eski fotokopi makineleri/tarayıcılar için SMB 1.0 protokolünü etkinleştiren buton ve uyarı mekanizması eklendi.
- ACL (Erişim Kontrol Listesi) şişmesini önlemek için izin eklenmeden önce mevcut kurallar denetlenir.
- Kurulumu Kaldır adımında veri kaybını önlemek için klasör boyutları hesaplanarak dinamik uyarı penceresi eklendi.
- Kaldırma işleminde Windows Kimlik Yöneticisindeki (cmdkey) eski OrtakErisim kayıtları temizlenir.
- [v2.5] 4. Sekme (Kaldırma) arayüzü güncellendi: Tarama ve Ortak Havuz için ayrı ayrı kaldırma butonları eklendi.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------------------------------------------------------------------------
# YÜKSEK ÇÖZÜNÜRLÜK (DPI) FARKINDALIĞI VE GÖRSEL STİLLER
# -------------------------------------------------------------------------
$dpiAware = @"
using System;
using System.Runtime.InteropServices;
public static class DpiFix {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
Add-Type -TypeDefinition $dpiAware
[DpiFix]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# -------------------------------------------------------------------------
# YÖNETİCİ (ADMIN) KONTROLÜ VE ARKADAKİ KONSOLU GİZLEME (v2.6 - Üste Taşındı)
# -------------------------------------------------------------------------
function Test-Admin {
    $currentUser = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $BetikYolu = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($BetikYolu)) { $BetikYolu = $MyInvocation.MyCommand.Path }

    try {
        $argList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$BetikYolu`""
        Start-Process powershell -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Yönetici izni alınırken hata oluştu veya işlem reddedildi.", "Yönetici İzni Gerekli", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    exit
}

# -------------------------------------------------------------------------
# DURUM (STATE) DOSYALARI - Kaldırma işleminde orijinal ayarlara dönebilmek için
# -------------------------------------------------------------------------
$script:StateDir = Join-Path $env:ProgramData "KlasorYonetimAraci"
$script:PowerBackupFile = Join-Path $script:StateDir "power_backup.json"
$script:FirewallBackupFile = Join-Path $script:StateDir "firewall_backup.json"

if (-not (Test-Path $script:StateDir)) {
    New-Item -Path $script:StateDir -ItemType Directory -Force | Out-Null
}

# -------------------------------------------------------------------------
# YARDIMCI FONKSİYONLAR
# -------------------------------------------------------------------------
function Test-PasswordComplexity {
    param(
        [string]$Password,
        [string]$UserNameToAvoid = "",
        [int]$MinLength = 8
    )

    $result = [PSCustomObject]@{
        IsValid = $true
        Reasons = @()
    }

    if ($Password.Length -lt $MinLength) {
        $result.IsValid = $false
        $result.Reasons += "en az $MinLength karakter olmalı"
    }

    $categoryCount = 0
    if ($Password -cmatch '[a-zçğıöşü]') { $categoryCount++ }
    if ($Password -cmatch '[A-ZÇĞIİÖŞÜ]') { $categoryCount++ }
    if ($Password -match '[0-9]') { $categoryCount++ }
    if ($Password -match '[^a-zA-Z0-9çğıöşüÇĞIİÖŞÜ]') { $categoryCount++ }

    if ($categoryCount -lt 3) {
        $result.IsValid = $false
        $result.Reasons += "büyük harf, küçük harf, rakam ve simgeden en az 3 kategoriyi içermeli"
    }

    if ($UserNameToAvoid -and $Password.ToLower().Contains($UserNameToAvoid.ToLower())) {
        $result.IsValid = $false
        $result.Reasons += "kullanıcı adını (`"$UserNameToAvoid`") içeremez"
    }

    return $result
}

function Show-PasswordInputDialog {
    param(
        [string]$Title = "Şifre Belirleyin",
        [string]$Prompt = "Lütfen bir şifre girin:",
        [int]$MinLength = 8,
        [string]$UserNameToAvoid = ""
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(420, 310)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $dlg.BackColor = [System.Drawing.Color]::WhiteSmoke

    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Text = $Prompt
    $lblPrompt.Location = New-Object System.Drawing.Point(15, 15)
    $lblPrompt.Size = New-Object System.Drawing.Size(370, 35)
    $dlg.Controls.Add($lblPrompt)

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "Gereksinim: en az $MinLength karakter; büyük harf, küçük harf, rakam ve simgeden en az 3 kategoriyi içermeli. Windows'un yerel güvenlik politikası buna göre çalışır."
    $lblHint.Location = New-Object System.Drawing.Point(15, 50)
    $lblHint.Size = New-Object System.Drawing.Size(370, 45)
    $lblHint.ForeColor = [System.Drawing.Color]::DimGray
    $lblHint.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $dlg.Controls.Add($lblHint)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Şifre:"
    $lblPass.Location = New-Object System.Drawing.Point(15, 100)
    $lblPass.AutoSize = $true
    $dlg.Controls.Add($lblPass)

    $txtPassword = New-Object System.Windows.Forms.TextBox
    $txtPassword.Location = New-Object System.Drawing.Point(110, 97)
    $txtPassword.Size = New-Object System.Drawing.Size(275, 24)
    $txtPassword.UseSystemPasswordChar = $true
    $dlg.Controls.Add($txtPassword)

    $lblConfirm = New-Object System.Windows.Forms.Label
    $lblConfirm.Text = "Şifre (Tekrar):"
    $lblConfirm.Location = New-Object System.Drawing.Point(15, 130)
    $lblConfirm.AutoSize = $true
    $dlg.Controls.Add($lblConfirm)

    $txtConfirm = New-Object System.Windows.Forms.TextBox
    $txtConfirm.Location = New-Object System.Drawing.Point(110, 127)
    $txtConfirm.Size = New-Object System.Drawing.Size(275, 24)
    $txtConfirm.UseSystemPasswordChar = $true
    $dlg.Controls.Add($txtConfirm)

    $chkShow = New-Object System.Windows.Forms.CheckBox
    $chkShow.Text = "Şifreyi göster"
    $chkShow.Location = New-Object System.Drawing.Point(110, 155)
    $chkShow.AutoSize = $true
    $chkShow.Add_CheckedChanged({
        $txtPassword.UseSystemPasswordChar = -not $chkShow.Checked
        $txtConfirm.UseSystemPasswordChar = -not $chkShow.Checked
    })
    $dlg.Controls.Add($chkShow)

    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Location = New-Object System.Drawing.Point(15, 182)
    $lblError.Size = New-Object System.Drawing.Size(370, 45)
    $lblError.ForeColor = [System.Drawing.Color]::Firebrick
    $dlg.Controls.Add($lblError)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Tamam"
    $btnOk.Location = New-Object System.Drawing.Point(200, 230)
    $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.FlatStyle = "Flat"
    $btnOk.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $btnOk.BackColor = [System.Drawing.Color]::White
    $btnOk.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "İptal"
    $btnCancel.Location = New-Object System.Drawing.Point(295, 230)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
    $btnCancel.BackColor = [System.Drawing.Color]::White
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dlg.Controls.Add($btnCancel)

    $script:PasswordDialogResult = $null

    $btnOk.Add_Click({
        $p1 = $txtPassword.Text
        $p2 = $txtConfirm.Text
        if ([string]::IsNullOrEmpty($p1)) {
            $lblError.Text = "Şifre boş olamaz."
            return
        }
        if ($p1 -ne $p2) {
            $lblError.Text = "Girilen şifreler eşleşmiyor."
            return
        }
        $check = Test-PasswordComplexity -Password $p1 -UserNameToAvoid $UserNameToAvoid -MinLength $MinLength
        if (-not $check.IsValid) {
            $lblError.Text = "Şifre kabul edilmedi: " + ($check.Reasons -join "; ") + "."
            return
        }
        $script:PasswordDialogResult = $p1
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $btnCancel.Add_Click({
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    [void]$dlg.ShowDialog()
    return $script:PasswordDialogResult
}

function Test-NetworkSharing {
    Update-Log "SMB servisi kontrol ediliyor..." "INFO"
    $Service = Get-Service LanmanServer -ErrorAction SilentlyContinue
    if ($Service) {
        if ($Service.StartType -ne "Automatic") {
            Set-Service -Name LanmanServer -StartupType Automatic
            Update-Log "SMB servisinin başlangıç türü Otomatik olarak ayarlandı." "SUCCESS"
        }
        if ($Service.Status -ne "Running") {
            Start-Service LanmanServer
        }
    }
    Update-Log "SMB servisi çalışıyor." "SUCCESS"
}

# --- GÜÇ AYARLARINI YEDEKLEME / GERİ YÜKLEME ---
function Get-PowerSettingSeconds {
    param([string]$SubGroup, [string]$Setting)
    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
    $acHex = ($output | Select-String "Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)").Matches.Groups[1].Value
    $dcHex = ($output | Select-String "Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)").Matches.Groups[1].Value
    return [PSCustomObject]@{
        AC = if ($acHex) { [Convert]::ToInt32($acHex, 16) } else { $null }
        DC = if ($dcHex) { [Convert]::ToInt32($dcHex, 16) } else { $null }
    }
}

function Backup-PowerSettingsIfNeeded {
    if (Test-Path $script:PowerBackupFile) { return }
    try {
        $standby = Get-PowerSettingSeconds -SubGroup "SUB_SLEEP" -Setting "STANDBYIDLE"
        $hibernate = Get-PowerSettingSeconds -SubGroup "SUB_SLEEP" -Setting "HIBERNATEIDLE"
        $backup = [PSCustomObject]@{
            StandbyAC   = $standby.AC
            StandbyDC   = $standby.DC
            HibernateAC = $hibernate.AC
            HibernateDC = $hibernate.DC
        }
        $backup | ConvertTo-Json | Set-Content -Path $script:PowerBackupFile -Encoding UTF8
        Update-Log "Orijinal güç ayarları yedeklendi (kaldırma sırasında geri yüklenecek)." "INFO"
    } catch {
        Update-Log "Güç ayarları yedeklenemedi: $($_.Exception.Message)" "WARNING"
    }
}

function Disable-SleepMode {
    Update-Log "Güç ayarları optimize ediliyor (Uyku Modu Kapatılıyor)..." "INFO"
    try {
        Backup-PowerSettingsIfNeeded
        powercfg.exe /change standby-timeout-ac 0
        powercfg.exe /change standby-timeout-dc 0
        powercfg.exe /change hibernate-timeout-ac 0
        powercfg.exe /change hibernate-timeout-dc 0
        Update-Log "Güç ayarları güncellendi: PC uykuya geçmeyecek." "SUCCESS"
    } catch {
        Update-Log "Güç ayarları değiştirilirken bir uyarı oluştu." "WARNING"
    }
}

function Restore-PowerSettings {
    if (-not (Test-Path $script:PowerBackupFile)) {
        Update-Log "Yedeklenmiş orijinal güç ayarı bulunamadı, güç ayarları değiştirilmedi." "INFO"
        return
    }
    try {
        $backup = Get-Content $script:PowerBackupFile -Raw | ConvertFrom-Json
        if ($null -ne $backup.StandbyAC)   { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $backup.StandbyAC }
        if ($null -ne $backup.StandbyDC)   { powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $backup.StandbyDC }
        if ($null -ne $backup.HibernateAC) { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE $backup.HibernateAC }
        if ($null -ne $backup.HibernateDC) { powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE $backup.HibernateDC }
        powercfg /setactive SCHEME_CURRENT
        Remove-Item $script:PowerBackupFile -Force -ErrorAction SilentlyContinue
        Update-Log "Güç ayarları kurulum öncesi haline geri döndürüldü." "SUCCESS"
    } catch {
        Update-Log "Güç ayarları geri yüklenirken hata: $($_.Exception.Message)" "WARNING"
    }
}

# --- GÜVENLİK DUVARI KURALLARINI YEDEKLEME / GERİ YÜKLEME ---
function Enable-SharingFirewallGroup {
    param([string]$GroupNameEn, [string]$GroupNameTr)

    $wasAlreadyEnabled = $false
    try {
        $rules = Get-NetFirewallRule -DisplayGroup $GroupNameEn -ErrorAction Stop
        $wasAlreadyEnabled = ($rules | Where-Object { $_.Enabled -eq "True" }).Count -eq $rules.Count -and $rules.Count -gt 0
        Enable-NetFirewallRule -DisplayGroup $GroupNameEn -ErrorAction Stop
    } catch {
        netsh advfirewall firewall set rule group="$GroupNameTr" new enable=Yes | Out-Null
    }

    $backup = @{}
    if (Test-Path $script:FirewallBackupFile) {
        $json = Get-Content $script:FirewallBackupFile -Raw | ConvertFrom-Json
        if ($json) {
            foreach ($prop in $json.psobject.properties) {
                $backup[$prop.Name] = $prop.Value
            }
        }
    }
    
    if (-not $backup.ContainsKey($GroupNameEn)) {
        $backup[$GroupNameEn] = -not $wasAlreadyEnabled 
    }
    $backup | ConvertTo-Json | Set-Content -Path $script:FirewallBackupFile -Encoding UTF8
}

function Restore-SharingFirewallGroups {
    if (-not (Test-Path $script:FirewallBackupFile)) { return }
    try {
        $json = Get-Content $script:FirewallBackupFile -Raw | ConvertFrom-Json
        if ($json) {
            foreach ($prop in $json.psobject.properties) {
                $group = $prop.Name
                $value = $prop.Value
                
                if ($value -eq $true) {
                    try {
                        Disable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
                        Update-Log "'$group' güvenlik duvarı kuralı, kurulum öncesi haline (kapalı) döndürüldü." "SUCCESS"
                    } catch {
                        # Türkçe sistemler için netsh alternatifi
                        $trGroup = $group
                        if ($group -eq "File and Printer Sharing") { $trGroup = "Dosya ve Yazıcı Paylaşımı" }
                        if ($group -eq "Network Discovery") { $trGroup = "Ağ Bulma" }
                        
                        try {
                            netsh advfirewall firewall set rule group="$trGroup" new enable=No | Out-Null
                            Update-Log "'$trGroup' güvenlik duvarı kuralı (netsh ile), kurulum öncesi haline döndürüldü." "SUCCESS"
                        } catch {
                            Update-Log "'$group' güvenlik duvarı kuralı geri alınamadı." "WARNING"
                        }
                    }
                }
            }
        }
        Remove-Item $script:FirewallBackupFile -Force -ErrorAction SilentlyContinue
    } catch {
        Update-Log "Güvenlik duvarı ayarları geri yüklenirken hata: $($_.Exception.Message)" "WARNING"
    }
}

# --- ORTAK YARDIMCI: KLASÖR + KISAYOL ---
function Initialize-TargetFolder {
    param([string]$FolderPath)
    if (-not (Test-Path $FolderPath)) {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        Update-Log "$FolderPath oluşturuldu." "SUCCESS"
    }
}

function New-DesktopShortcut {
    param([string]$ShortcutName, [string]$TargetPath)
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $ShortcutPath = Join-Path $DesktopPath "$ShortcutName.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WScriptShell)
    Update-Log "Masaüstüne '$ShortcutName' kısayolu eklendi." "SUCCESS"
}

# --- ARAYÜZ (FORM) ANA AYARLARI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Çok Amaçlı Klasör Yönetim Aracı"
$form.Size = New-Object System.Drawing.Size(720, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
# Yeni Modern Font ve Arka Plan (UI İyileştirmesi)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# --- GELİŞMİŞ LOG FONKSİYONU ---
function Update-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    switch ($Level) {
        "INFO"    { $Prefix = "[BİLGİ]" }
        "SUCCESS" { $Prefix = "[BAŞARILI]" }
        "WARNING" { $Prefix = "[UYARI]" }
        "ERROR"   { $Prefix = "[HATA]" }
    }
    $Text = "{0} {1} {2}`r`n" -f (Get-Date -Format "HH:mm:ss"), $Prefix, $Message
    $txtLog.AppendText($Text)
}

# -------------------------------------------------------------------------
# SEKME (TAB) KONTROLÜ
# -------------------------------------------------------------------------
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(680, 220)
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Multiline = $false
$form.Controls.Add($tabControl)

# --- SEKME 1: TARAMA KLASÖRÜ ---
$tabScan = New-Object System.Windows.Forms.TabPage
$tabScan.Text = "1. Tarama Klasörü"
$tabScan.BackColor = [System.Drawing.Color]::White
$tabControl.TabPages.Add($tabScan)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Tarama Klasörünü Kur (C:\Tarama)"
$btnScan.Size = New-Object System.Drawing.Size(640, 45)
$btnScan.Location = New-Object System.Drawing.Point(15, 20)
$btnScan.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
$btnScan.FlatStyle = "Flat"
$btnScan.FlatAppearance.BorderSize = 1
$btnScan.FlatAppearance.BorderColor = [System.Drawing.Color]::Khaki
$btnScan.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnScan.Add_Click({
    Update-Log "Tarayıcı/Yazıcı kurulumu başlatılıyor..." "INFO"
    try {
        Test-NetworkSharing
        Disable-SleepMode

        Enable-SharingFirewallGroup -GroupNameEn "File and Printer Sharing" -GroupNameTr "Dosya ve Yazıcı Paylaşımı"
        Enable-SharingFirewallGroup -GroupNameEn "Network Discovery" -GroupNameTr "Ağ Bulma"

        $FolderPath = "C:\Tarama"
        $ShareName = "Tarama$"
        $UserName = $env:USERNAME

        Initialize-TargetFolder -FolderPath $FolderPath

        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
        if (-not $existingShare) {
            cmd.exe /c "net share $ShareName=`"$FolderPath`" /grant:everyone,CHANGE" | Out-Null
            Update-Log "Klasör ağa gizli (Tarama$) olarak paylaşıldı (tarayıcı erişimi için Everyone,CHANGE)." "SUCCESS"
        }

        # ACL Anti-Bloat Kontrolü (v2.6 - Tam Eşleşme)
        $Acl = Get-Acl -Path $FolderPath
        $ident = "$env:COMPUTERNAME\$UserName"
        $ruleExists = $Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident -and $_.FileSystemRights -match "FullControl" }
        
        if (-not $ruleExists) {
            $Permission = $ident, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $Permission
            $Acl.AddAccessRule($AccessRule)
            Set-Acl -Path $FolderPath -AclObject $Acl
            Update-Log "Klasör izinleri (ACL) uygulandı." "SUCCESS"
        }

        New-DesktopShortcut -ShortcutName "Tarama" -TargetPath $FolderPath

        Start-Process explorer.exe $FolderPath
        Update-Log "TARAMA İŞLEMİ TAMAMLANDI!" "SUCCESS"

        $btnScan.Text = "Tarama Klasörü Zaten Kurulu (C:\Tarama)"
        $btnScan.BackColor = [System.Drawing.Color]::WhiteSmoke

        $msgText = "Tarama Kurulumu başarıyla tamamlandı!`n`nÖNEMLİ NOT: Ağ yazıcısının/fotokopi makinesinin web arayüzüne ayarları girerken klasör yolu (path) kısmına tam olarak şunu yazmayı unutmayın:`n`nTarama$"
        [System.Windows.Forms.MessageBox]::Show($msgText, "Kurulum Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Update-Log "$($_.Exception.Message)" "ERROR"
    }
})
$tabScan.Controls.Add($btnScan)

# SMB 1.0 AÇMA BUTONU
$btnSmb1 = New-Object System.Windows.Forms.Button
$btnSmb1.Text = "Eski Tarayıcılar İçin SMB 1.0 Desteğini Aç (Önerilmez)"
$btnSmb1.Size = New-Object System.Drawing.Size(640, 35)
$btnSmb1.Location = New-Object System.Drawing.Point(15, 75)
$btnSmb1.BackColor = [System.Drawing.Color]::MistyRose
$btnSmb1.FlatStyle = "Flat"
$btnSmb1.FlatAppearance.BorderSize = 1
$btnSmb1.FlatAppearance.BorderColor = [System.Drawing.Color]::LightCoral
$btnSmb1.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSmb1.Add_Click({
    $confirmSmb = [System.Windows.Forms.MessageBox]::Show(
        "DİKKAT: SMB 1.0 çok eski ve güvenlik açığı barındıran bir protokoldür. Sadece tarayıcınız çok eskiyse ve başka türlü klasöre yazamıyorsa açmalısınız.`n`nBu işlem bilgisayarınızın YENİDEN BAŞLATILMASINI gerektirebilir. Onaylıyor musunuz?",
        "Güvenlik Uyarısı",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirmSmb -eq [System.Windows.Forms.DialogResult]::Yes) {
        Update-Log "SMB 1.0 aktifleştiriliyor, lütfen bekleyin (Sürebilir)..." "INFO"
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -All -NoRestart -ErrorAction Stop | Out-Null
            Update-Log "SMB 1.0 başarıyla açıldı. Sistemi yeniden başlatmanız gerekebilir." "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("SMB 1.0 başarıyla açıldı.`n`nDeğişikliklerin etkili olması için lütfen işlemleriniz bitince bilgisayarınızı YENİDEN BAŞLATIN.", "İşlem Başarılı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Update-Log "SMB 1.0 açılamadı: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Update-Log "SMB 1.0 aktifleştirme işlemi iptal edildi." "INFO"
    }
})
$tabScan.Controls.Add($btnSmb1)

# SMB 1.0 KAPATMA BUTONU
$btnSmb1Disable = New-Object System.Windows.Forms.Button
$btnSmb1Disable.Text = "SMB 1.0 Desteğini Kapat (Güvenlik İçin Önerilir)"
$btnSmb1Disable.Size = New-Object System.Drawing.Size(640, 35)
$btnSmb1Disable.Location = New-Object System.Drawing.Point(15, 115)
$btnSmb1Disable.BackColor = [System.Drawing.Color]::Honeydew
$btnSmb1Disable.FlatStyle = "Flat"
$btnSmb1Disable.FlatAppearance.BorderSize = 1
$btnSmb1Disable.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkSeaGreen
$btnSmb1Disable.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSmb1Disable.Add_Click({
    $confirmSmbDisable = [System.Windows.Forms.MessageBox]::Show(
        "SMB 1.0 protokolü tamamen devre dışı bırakılacak. Bu işlem bilgisayarınızın YENİDEN BAŞLATILMASINI gerektirebilir. Onaylıyor musunuz?",
        "Kapatma Onayı",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirmSmbDisable -eq [System.Windows.Forms.DialogResult]::Yes) {
        Update-Log "SMB 1.0 devre dışı bırakılıyor, lütfen bekleyin (Sürebilir)..." "INFO"
        try {
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction Stop | Out-Null
            Update-Log "SMB 1.0 başarıyla kapatıldı. Sistemi yeniden başlatmanız gerekebilir." "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("SMB 1.0 başarıyla kapatıldı.`n`nDeğişikliklerin tam olarak etkili olması için lütfen bilgisayarınızı YENİDEN BAŞLATIN.", "İşlem Başarılı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Update-Log "SMB 1.0 kapatılamadı: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Update-Log "SMB 1.0 kapatma işlemi iptal edildi." "INFO"
    }
})
$tabScan.Controls.Add($btnSmb1Disable)

# --- SEKME 2: ORTAK ÇALIŞMA KLASÖRÜ (ANA BİLGİSAYAR) ---
$tabHost = New-Object System.Windows.Forms.TabPage
$tabHost.Text = "2. Ortak Klasör (Ana PC)"
$tabHost.BackColor = [System.Drawing.Color]::White
$tabControl.TabPages.Add($tabHost)

$btnHost = New-Object System.Windows.Forms.Button
$btnHost.Text = "Ortak Havuz Altyapısını Kur (C:\OrtakHavuz)"
$btnHost.Size = New-Object System.Drawing.Size(640, 40)
$btnHost.Location = New-Object System.Drawing.Point(15, 15)
$btnHost.BackColor = [System.Drawing.Color]::Honeydew
$btnHost.FlatStyle = "Flat"
$btnHost.FlatAppearance.BorderSize = 1
$btnHost.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkSeaGreen
$btnHost.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnHost.Add_Click({
    $FolderPath = "C:\OrtakHavuz"
    $ShareName = "OrtakHavuz"
    $OrtakUser = "OrtakErisim"
    $AdminUser = $env:USERNAME

    $accountCreated = $false
    $plainPassword = $null
    $accountAlreadyExists = [bool](Get-LocalUser -Name $OrtakUser -ErrorAction SilentlyContinue)

    if (-not $accountAlreadyExists) {
        $promptText = "'$OrtakUser' ağ erişim hesabı için bir şifre belirleyin:"
        while ($true) {
            $plainPassword = Show-PasswordInputDialog -Title "OrtakErisim Şifresi" -Prompt $promptText -UserNameToAvoid $OrtakUser
            if ([string]::IsNullOrEmpty($plainPassword)) {
                Update-Log "İşlem iptal edildi: Şifre girilmedi." "WARNING"
                return
            }

            try {
                $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
                $Params = @{
                    Name                 = $OrtakUser
                    Password             = $securePassword
                    PasswordNeverExpires = $true
                    Description          = "Ağ ortak erişim hesabı"
                }
                New-LocalUser @Params -ErrorAction Stop | Out-Null
                Set-LocalUser -Name $OrtakUser -PasswordNeverExpires $true
                $accountCreated = $true
                Update-Log "'$OrtakUser' hesabı oluşturuldu." "SUCCESS"
                break
            } catch {
                Update-Log "Şifre bu bilgisayarın güvenlik politikası tarafından reddedildi: $($_.Exception.Message)" "WARNING"
                $promptText = "Şifre kabul edilmedi. Lütfen bu bilgisayarın parola politikasına uygun farklı bir şifre girin:"
            }
        }
    }

    Update-Log "Ortak Havuz altyapısı kuruluyor..." "INFO"
    try {
        Test-NetworkSharing
        Disable-SleepMode

        Enable-SharingFirewallGroup -GroupNameEn "File and Printer Sharing" -GroupNameTr "Dosya ve Yazıcı Paylaşımı"

        Initialize-TargetFolder -FolderPath $FolderPath

        $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
        if (-not $existingShare) {
            New-SmbShare -Name $ShareName -Path $FolderPath `
                -ChangeAccess "$env:COMPUTERNAME\$OrtakUser" `
                -FullAccess "$env:COMPUTERNAME\$AdminUser" | Out-Null
            Update-Log "Klasör ağ paylaşıma açıldı (sadece $OrtakUser ve $AdminUser erişimiyle)." "SUCCESS"
        } else {
            Grant-SmbShareAccess -Name $ShareName -AccountName "$env:COMPUTERNAME\$OrtakUser" -AccessRight Change -Force -ErrorAction SilentlyContinue | Out-Null
            Grant-SmbShareAccess -Name $ShareName -AccountName "$env:COMPUTERNAME\$AdminUser" -AccessRight Full -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # ACL Anti-Bloat Kontrolü (v2.6 - Tam Eşleşme)
        $Acl = Get-Acl -Path $FolderPath
        
        $ident1 = "$env:COMPUTERNAME\$OrtakUser"
        $rule1Exists = $Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident1 -and $_.FileSystemRights -match "Modify" }
        if (-not $rule1Exists) {
            $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ($ident1, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
        }

        $ident2 = "$env:COMPUTERNAME\$AdminUser"
        $rule2Exists = $Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident2 -and $_.FileSystemRights -match "FullControl" }
        if (-not $rule2Exists) {
            $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ($ident2, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        }

        Set-Acl -Path $FolderPath -AclObject $Acl
        Update-Log "Ortak havuz ACL izinleri denetlendi." "SUCCESS"

        New-DesktopShortcut -ShortcutName "OrtakHavuz" -TargetPath $FolderPath

        Start-Process explorer.exe $FolderPath
        Update-Log "ORTAK HAVUZ İŞLEMİ TAMAMLANDI!" "SUCCESS"

        $btnHost.Text = "Ortak Havuz Zaten Kurulu (C:\OrtakHavuz)"
        $btnHost.BackColor = [System.Drawing.Color]::WhiteSmoke

        if ($accountCreated) {
            Set-Clipboard $plainPassword
            $script:LastPassword = $plainPassword
            Update-Log "Şifre panoya kopyalandı." "SUCCESS"

            $DesktopPath = [Environment]::GetFolderPath('Desktop')
            $InfoFile = Join-Path $DesktopPath "Ortak_Klasor_Baglanti_Bilgileri.txt"
            $InfoContent = "--- ORTAK HAVUZ BAĞLANTI BİLGİLERİ ---`r`nAna Bilgisayar Adı: $env:COMPUTERNAME`r`nKullanıcı Adı: $OrtakUser`r`nŞifre: $plainPassword`r`n`r`nBu dosyayı güvenli bir yerde saklayın."
            Set-Content -Path $InfoFile -Value $InfoContent -Encoding UTF8
            Update-Log "Bağlantı bilgileri masaüstüne txt olarak kaydedildi." "SUCCESS"
            Update-Log "GÜVENLİK UYARISI: Bu txt dosyası şifreyi düz metin içerir. Diğer bilgisayarlara ilettikten sonra silmeniz veya güvenli bir yere taşımanız önerilir." "WARNING"

            $msgText = "Ortak Klasör başarıyla oluşturuldu!`n`n" +
                       "Güç ayarları optimize edildi (Uyku Modu kapatıldı).`n`n" +
                       "'$OrtakUser' hesabı için OLUŞTURULAN ŞİFRE (Masaüstüne Kaydedildi):`n$plainPassword`n`n" +
                       "Diğer bilgisayarlarda yapmanız gerekenler:`n1. Bu program o bilgisayarda çalıştırın.`n2. '3. Diğer PC'den Bağlan' sekmesine geçin.`n3. 'Ana Bilgisayarın Adı' kısmına tam olarak şunu yazın: $env:COMPUTERNAME`n4. Şifreyi yapıştırın.`n5. 'Ortak Havuza Bağlan' butonuna tıklayın.`n`nNOT: Bağlantı bilgileri masaüstünüzdeki txt dosyasında düz metin olarak duruyor; iletim sonrası silmeniz önerilir."
        } else {
            $msgText = "Ortak Klasör altyapısı zaten kurulu ve denetlendi. Uyku modu ayarları güvenceye alındı."
        }
        [System.Windows.Forms.MessageBox]::Show($msgText, "Kurulum Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Update-Log "$($_.Exception.Message)" "ERROR"
    }
})
$tabHost.Controls.Add($btnHost)

$btnCopyPC = New-Object System.Windows.Forms.Button
$btnCopyPC.Text = "Bilgisayar Adını Kopyala"
$btnCopyPC.Size = New-Object System.Drawing.Size(312, 30)
$btnCopyPC.Location = New-Object System.Drawing.Point(15, 62)
$btnCopyPC.FlatStyle = "Flat"
$btnCopyPC.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnCopyPC.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyPC.Add_Click({
    Set-Clipboard $env:COMPUTERNAME
    Update-Log "Bilgisayar adı panoya kopyalandı." "SUCCESS"
})
$tabHost.Controls.Add($btnCopyPC)

$btnCopyPass = New-Object System.Windows.Forms.Button
$btnCopyPass.Text = "Son Şifreyi Kopyala"
$btnCopyPass.Size = New-Object System.Drawing.Size(312, 30)
$btnCopyPass.Location = New-Object System.Drawing.Point(343, 62)
$btnCopyPass.FlatStyle = "Flat"
$btnCopyPass.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray
$btnCopyPass.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyPass.Add_Click({
    if ($script:LastPassword) {
        Set-Clipboard $script:LastPassword
        Update-Log "Şifre panoya kopyalandı." "SUCCESS"
    } else {
        Update-Log "Bellekte aktif bir yeni şifre bulunamadı." "WARNING"
    }
})
$tabHost.Controls.Add($btnCopyPass)

# --- SEKME 3: ORTAK ÇALIŞMA KLASÖRÜ (DİĞER BİLGİSAYARLAR) ---
$tabClient = New-Object System.Windows.Forms.TabPage
$tabClient.Text = "3. Diğer PC'den Bağlan"
$tabClient.BackColor = [System.Drawing.Color]::White
$tabControl.TabPages.Add($tabClient)

$lblHost = New-Object System.Windows.Forms.Label
$lblHost.Text = "Ana Bilgisayarın Adı:"
$lblHost.Location = New-Object System.Drawing.Point(20, 20)
$lblHost.AutoSize = $true
$tabClient.Controls.Add($lblHost)

$txtHost = New-Object System.Windows.Forms.TextBox
$txtHost.Location = New-Object System.Drawing.Point(170, 17)
$txtHost.Size = New-Object System.Drawing.Size(260, 24)
$tabClient.Controls.Add($txtHost)

$lblPass = New-Object System.Windows.Forms.Label
$lblPass.Text = "OrtakErisim Şifresi:"
$lblPass.Location = New-Object System.Drawing.Point(20, 55)
$lblPass.AutoSize = $true
$tabClient.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.TextBox
$txtPass.Location = New-Object System.Drawing.Point(170, 52)
$txtPass.Size = New-Object System.Drawing.Size(260, 24)
$txtPass.UseSystemPasswordChar = $true
$tabClient.Controls.Add($txtPass)

$btnClient = New-Object System.Windows.Forms.Button
$btnClient.Text = "Ortak Havuza Bağlan"
$btnClient.Size = New-Object System.Drawing.Size(160, 32)
$btnClient.Location = New-Object System.Drawing.Point(270, 85)
$btnClient.BackColor = [System.Drawing.Color]::AliceBlue
$btnClient.FlatStyle = "Flat"
$btnClient.FlatAppearance.BorderColor = [System.Drawing.Color]::LightSteelBlue
$btnClient.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClient.Add_Click({
    $hostName = $txtHost.Text.Trim()
    $passwordText = $txtPass.Text

    if ([string]::IsNullOrEmpty($hostName)) {
        Update-Log "HATA: Lütfen ana bilgisayarın adını girin!" "ERROR"
        return
    }
    if ([string]::IsNullOrEmpty($passwordText)) {
        Update-Log "HATA: Lütfen OrtakErisim hesabının şifresini girin!" "ERROR"
        return
    }

    Update-Log "$hostName hedefine erişim kontrol ediliyor..." "INFO"
    if (-not (Test-Connection -ComputerName $hostName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Update-Log "HATA: $hostName ağda bulunamadı! Cihaz kapalı veya ağ adı yanlış." "ERROR"
        return
    }

    $remotePath = "\\$hostName\OrtakHavuz"
    Update-Log "Bağlantı deneniyor ve kimlik bilgileri kaydediliyor..." "INFO"

    try {
        # v2.6 - Komut Enjeksiyonu Koruması (Doğrudan cmdkey.exe çağrısı)
        & cmdkey.exe /add:$hostName /user:"$hostName\OrtakErisim" /pass:$passwordText | Out-Null
        Start-Sleep -Seconds 1

        $DesktopPath = [Environment]::GetFolderPath('Desktop')
        $ShortcutPath = Join-Path $DesktopPath "OrtakHavuz_Baglantisi.lnk"
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $remotePath
        $Shortcut.Save()
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WScriptShell)

        Start-Process explorer.exe $remotePath
        Update-Log "BAŞARILI! Şifre kaydedildi ve Masaüstüne kısayol oluşturuldu." "SUCCESS"
        
        [System.Windows.Forms.MessageBox]::Show("Bağlantı başarılı!`n`nMasaüstünüze 'OrtakHavuz_Baglantisi' adında bir kısayol eklendi. Çift tıklayarak şifre sormadan girebilirsiniz.", "Başarılı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Update-Log "$($_.Exception.Message)" "ERROR"
    }
})
$tabClient.Controls.Add($btnClient)

# --- SEKME 4: SİSTEMİ KALDIR / TEMİZLE ---
$tabRemove = New-Object System.Windows.Forms.TabPage
$tabRemove.Text = "4. Kurulumu Kaldır"
$tabRemove.BackColor = [System.Drawing.Color]::White
$tabControl.TabPages.Add($tabRemove)

$lblRemoveInfo = New-Object System.Windows.Forms.Label
$lblRemoveInfo.Text = "Kaldırmak istediğiniz bileşeni seçin. İlgili klasörler, ağ paylaşımları, kullanıcı hesapları ve masaüstü kısayolları sistemden temizlenecektir."
$lblRemoveInfo.Location = New-Object System.Drawing.Point(15, 15)
$lblRemoveInfo.Size = New-Object System.Drawing.Size(640, 40)
$tabRemove.Controls.Add($lblRemoveInfo)

# 1. TARAMA KALDIR BUTONU
$btnRemoveTarama = New-Object System.Windows.Forms.Button
$btnRemoveTarama.Text = "Sadece Tarama Klasörünü Kaldır"
$btnRemoveTarama.Size = New-Object System.Drawing.Size(312, 45)
$btnRemoveTarama.Location = New-Object System.Drawing.Point(15, 60)
$btnRemoveTarama.BackColor = [System.Drawing.Color]::LemonChiffon
$btnRemoveTarama.FlatStyle = "Flat"
$btnRemoveTarama.FlatAppearance.BorderColor = [System.Drawing.Color]::Khaki
$btnRemoveTarama.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRemoveTarama.Add_Click({
    $taramaBoyutMB = 0
    if (Test-Path "C:\Tarama") {
        $taramaBoyutMB = [math]::Round(((Get-ChildItem "C:\Tarama" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
    }

    $uyariMetni = "Tarama klasörü, ağ paylaşımı (Tarama$) ve masaüstü kısayolu silinecektir."
    if ($taramaBoyutMB -gt 0) {
        $uyariMetni += "`n`n⚠️ DİKKAT: C:\Tarama içinde $taramaBoyutMB MB veri bulunuyor. KALICI OLARAK SİLİNECEKTİR!"
    }
    $uyariMetni += "`n`nİşlemi onaylıyor musunuz?"

    $confirm = [System.Windows.Forms.MessageBox]::Show($uyariMetni, "Tarama Kaldırma Onayı", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)

    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Update-Log "Tarama klasörü temizliği başlatılıyor..." "INFO"
        try {
            Remove-SmbShare -Name "Tarama$" -Force -ErrorAction SilentlyContinue
            Update-Log "Tarama ağ paylaşımı kapatıldı." "SUCCESS"

            $DesktopPath = [Environment]::GetFolderPath('Desktop')
            $ShortcutTarama = Join-Path $DesktopPath "Tarama.lnk"
            if (Test-Path $ShortcutTarama) { Remove-Item $ShortcutTarama -Force }

            if (Test-Path "C:\Tarama") {
                Remove-Item "C:\Tarama" -Recurse -Force -ErrorAction SilentlyContinue
                Update-Log "C:\Tarama klasörü silindi." "SUCCESS"
            }

            $btnScan.Text = "Tarama Klasörünü Kur (C:\Tarama)"
            $btnScan.BackColor = [System.Drawing.Color]::LightGoldenrodYellow

            # Eğer ortak havuz da yoksa (veya daha önce kaldırılmışsa) güç/güvenlik duvarı ayarlarını sıfırla
            if (-not (Test-Path "C:\OrtakHavuz")) {
                Restore-PowerSettings
                Restore-SharingFirewallGroups
                Update-Log "Sistemde başka paylaşım kalmadığı için güç/güvenlik duvarı ayarları sıfırlandı." "INFO"
            }

            [System.Windows.Forms.MessageBox]::Show("Tarama klasörü ve bileşenleri başarıyla kaldırıldı.", "Temizlik Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Update-Log "$($_.Exception.Message)" "ERROR"
        }
    }
})
$tabRemove.Controls.Add($btnRemoveTarama)

# 2. ORTAK HAVUZ KALDIR BUTONU
$btnRemoveOrtak = New-Object System.Windows.Forms.Button
$btnRemoveOrtak.Text = "Sadece Ortak Havuzu Kaldır"
$btnRemoveOrtak.Size = New-Object System.Drawing.Size(312, 45)
$btnRemoveOrtak.Location = New-Object System.Drawing.Point(343, 60)
$btnRemoveOrtak.BackColor = [System.Drawing.Color]::Honeydew
$btnRemoveOrtak.FlatStyle = "Flat"
$btnRemoveOrtak.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkSeaGreen
$btnRemoveOrtak.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRemoveOrtak.Add_Click({
    $ortakBoyutMB = 0
    if (Test-Path "C:\OrtakHavuz") {
        $ortakBoyutMB = [math]::Round(((Get-ChildItem "C:\OrtakHavuz" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
    }

    $uyariMetni = "Ortak Havuz klasörü, ağ paylaşımı, OrtakErisim hesabı, kayıtlı şifreler ve kısayollar silinecektir."
    if ($ortakBoyutMB -gt 0) {
        $uyariMetni += "`n`n⚠️ DİKKAT: C:\OrtakHavuz içinde $ortakBoyutMB MB veri bulunuyor. KALICI OLARAK SİLİNECEKTİR!"
    }
    $uyariMetni += "`n`nİşlemi onaylıyor musunuz?"

    $confirm = [System.Windows.Forms.MessageBox]::Show($uyariMetni, "Ortak Havuz Kaldırma Onayı", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)

    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Update-Log "Ortak Havuz temizliği başlatılıyor..." "INFO"
        try {
            try {
                $cmdkeyCikti = cmdkey /list | Out-String
                $satirlar = $cmdkeyCikti -split "`n"
                $hedef = ""
                foreach ($satir in $satirlar) {
                    if ($satir -match "Hedef:\s*(.*)") { $hedef = $matches[1].Trim() }
                    elseif ($satir -match "Target:\s*(.*)") { $hedef = $matches[1].Trim() }
                    
                    if ($satir -match "OrtakErisim" -and $hedef) {
                        cmdkey /delete:$hedef 2>&1 | Out-Null
                        Update-Log "Kayıtlı kimlik bilgisi silindi: $hedef" "SUCCESS"
                        $hedef = ""
                    }
                }
            } catch { }

            Remove-SmbShare -Name "OrtakHavuz" -Force -ErrorAction SilentlyContinue
            Update-Log "Ortak Havuz paylaşımı kapatıldı." "SUCCESS"

            if (Get-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue
                Update-Log "'OrtakErisim' kullanıcı hesabı silindi." "SUCCESS"
            }

            $DesktopPath = [Environment]::GetFolderPath('Desktop')
            $ShortcutOrtak = Join-Path $DesktopPath "OrtakHavuz_Baglantisi.lnk"
            $ShortcutOrtakAna = Join-Path $DesktopPath "OrtakHavuz.lnk"
            $TxtSifre = Join-Path $DesktopPath "Ortak_Klasor_Baglanti_Bilgileri.txt"
            if (Test-Path $ShortcutOrtak) { Remove-Item $ShortcutOrtak -Force }
            if (Test-Path $ShortcutOrtakAna) { Remove-Item $ShortcutOrtakAna -Force }
            if (Test-Path $TxtSifre) { Remove-Item $TxtSifre -Force }

            if (Test-Path "C:\OrtakHavuz") {
                Remove-Item "C:\OrtakHavuz" -Recurse -Force -ErrorAction SilentlyContinue
                Update-Log "C:\OrtakHavuz klasörü silindi." "SUCCESS"
            }

            $btnHost.Text = "Ortak Havuz Altyapısını Kur (C:\OrtakHavuz)"
            $btnHost.BackColor = [System.Drawing.Color]::LightGreen

            # Eğer tarama klasörü de yoksa güç/güvenlik duvarı ayarlarını sıfırla
            if (-not (Test-Path "C:\Tarama")) {
                Restore-PowerSettings
                Restore-SharingFirewallGroups
                Update-Log "Sistemde başka paylaşım kalmadığı için güç/güvenlik duvarı ayarları sıfırlandı." "INFO"
            }

            [System.Windows.Forms.MessageBox]::Show("Ortak Havuz ve bileşenleri başarıyla kaldırıldı.", "Temizlik Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Update-Log "$($_.Exception.Message)" "ERROR"
        }
    }
})
$tabRemove.Controls.Add($btnRemoveOrtak)

# 3. HER İKİSİNİ DE KALDIR BUTONU (TAM TEMİZLİK)
$btnRemoveAll = New-Object System.Windows.Forms.Button
$btnRemoveAll.Text = "Her İkisini de Kaldır ve Tamamen Temizle"
$btnRemoveAll.Size = New-Object System.Drawing.Size(640, 45)
$btnRemoveAll.Location = New-Object System.Drawing.Point(15, 115)
$btnRemoveAll.BackColor = [System.Drawing.Color]::MistyRose
$btnRemoveAll.FlatStyle = "Flat"
$btnRemoveAll.FlatAppearance.BorderColor = [System.Drawing.Color]::LightCoral
$btnRemoveAll.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRemoveAll.Add_Click({
    $ortakBoyutMB = 0
    if (Test-Path "C:\OrtakHavuz") {
        $ortakBoyutMB = [math]::Round(((Get-ChildItem "C:\OrtakHavuz" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
    }
    $taramaBoyutMB = 0
    if (Test-Path "C:\Tarama") {
        $taramaBoyutMB = [math]::Round(((Get-ChildItem "C:\Tarama" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
    }

    $uyariMetni = "Oluşturulan tüm paylaşımlar, OrtakErisim hesabı ve kısayollar silinecek; güç ve güvenlik duvarı ayarları orijinal haline döndürülecektir."
    
    if ($ortakBoyutMB -gt 0 -or $taramaBoyutMB -gt 0) {
        $uyariMetni += "`n`n⚠️ DİKKAT: KLASÖRLERDE VERİ BULUNUYOR!"
        if ($ortakBoyutMB -gt 0) { $uyariMetni += "`n- C:\OrtakHavuz ($ortakBoyutMB MB veri)" }
        if ($taramaBoyutMB -gt 0) { $uyariMetni += "`n- C:\Tarama ($taramaBoyutMB MB veri)" }
        $uyariMetni += "`n`nDevam ederseniz bu dosyaların TAMAMI KALICI OLARAK SİLİNECEKTİR.`nİşlemi onaylıyor musunuz?"
    } else {
        $uyariMetni += "`n`nİşlemi onaylıyor musunuz?"
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $uyariMetni,
        "Tam Temizlik Onayı",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Update-Log "Sistem temizliği başlatılıyor..." "INFO"
        try {
            try {
                $cmdkeyCikti = cmdkey /list | Out-String
                $satirlar = $cmdkeyCikti -split "`n"
                $hedef = ""
                foreach ($satir in $satirlar) {
                    if ($satir -match "Hedef:\s*(.*)") { $hedef = $matches[1].Trim() }
                    elseif ($satir -match "Target:\s*(.*)") { $hedef = $matches[1].Trim() }
                    
                    if ($satir -match "OrtakErisim" -and $hedef) {
                        cmdkey /delete:$hedef 2>&1 | Out-Null
                        Update-Log "Kayıtlı kimlik bilgisi silindi: $hedef" "SUCCESS"
                        $hedef = ""
                    }
                }
            } catch { }

            Remove-SmbShare -Name "OrtakHavuz" -Force -ErrorAction SilentlyContinue
            Remove-SmbShare -Name "Tarama$" -Force -ErrorAction SilentlyContinue
            Update-Log "Ağ paylaşımları kapatıldı." "SUCCESS"

            if (Get-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue
                Update-Log "'OrtakErisim' kullanıcı hesabı silindi." "SUCCESS"
            }

            $DesktopPath = [Environment]::GetFolderPath('Desktop')
            $ShortcutOrtak = Join-Path $DesktopPath "OrtakHavuz_Baglantisi.lnk"
            $ShortcutOrtakAna = Join-Path $DesktopPath "OrtakHavuz.lnk"
            $ShortcutTarama = Join-Path $DesktopPath "Tarama.lnk"
            $TxtSifre = Join-Path $DesktopPath "Ortak_Klasor_Baglanti_Bilgileri.txt"
            if (Test-Path $ShortcutOrtak) { Remove-Item $ShortcutOrtak -Force }
            if (Test-Path $ShortcutOrtakAna) { Remove-Item $ShortcutOrtakAna -Force }
            if (Test-Path $ShortcutTarama) { Remove-Item $ShortcutTarama -Force }
            if (Test-Path $TxtSifre) { Remove-Item $TxtSifre -Force }
            Update-Log "Masaüstü kalıntıları temizlendi." "SUCCESS"

            if (Test-Path "C:\OrtakHavuz") {
                Remove-Item "C:\OrtakHavuz" -Recurse -Force -ErrorAction SilentlyContinue
                Update-Log "C:\OrtakHavuz klasörü silindi." "SUCCESS"
            }
            if (Test-Path "C:\Tarama") {
                Remove-Item "C:\Tarama" -Recurse -Force -ErrorAction SilentlyContinue
                Update-Log "C:\Tarama klasörü silindi." "SUCCESS"
            }

            Restore-PowerSettings
            Restore-SharingFirewallGroups

            $btnScan.Text = "Tarama Klasörünü Kur (C:\Tarama)"
            $btnScan.BackColor = [System.Drawing.Color]::WhiteSmoke
            $btnHost.Text = "Ortak Havuz Altyapısını Kur (C:\OrtakHavuz)"
            $btnHost.BackColor = [System.Drawing.Color]::WhiteSmoke

            [System.Windows.Forms.MessageBox]::Show("Tüm bileşenler başarıyla kaldırıldı, güç ve güvenlik duvarı ayarları kurulum öncesi haline döndürüldü.", "Temizlik Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Update-Log "SİSTEM TAMAMEN TEMİZLENDİ." "SUCCESS"
        } catch {
            Update-Log "$($_.Exception.Message)" "ERROR"
        }
    }
})
$tabRemove.Controls.Add($btnRemoveAll)

# -------------------------------------------------------------------------
# DURUM (LOG) EKRANI
# -------------------------------------------------------------------------
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "İşlem Durumu ve Bilgilendirmeler:"
$lblLog.Location = New-Object System.Drawing.Point(10, 235)
$lblLog.AutoSize = $true
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Size = New-Object System.Drawing.Size(680, 300)
$txtLog.Location = New-Object System.Drawing.Point(10, 255)
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($txtLog)

# --- BAŞLANGIÇ SİSTEM KONTROLÜ ---
function Check-SystemStatus {
    Update-Log "Sistem başlangıç kontrolü yapılıyor..." "INFO"
    $taramaExists = Test-Path "C:\Tarama"
    $ortakExists = Test-Path "C:\OrtakHavuz"

    if ($taramaExists) {
        $btnScan.Text = "Tarama Klasörü Zaten Kurulu (C:\Tarama)"
        $btnScan.BackColor = [System.Drawing.Color]::WhiteSmoke
    }
    if ($ortakExists) {
        $btnHost.Text = "Ortak Havuz Zaten Kurulu (C:\OrtakHavuz)"
        $btnHost.BackColor = [System.Drawing.Color]::WhiteSmoke
    }
}

# --- BAŞLANGIÇ LOGLARI ---
Update-Log "PowerShell sürümü: $($PSVersionTable.PSVersion)" "INFO"
Update-Log "Kullanıcı: $(whoami)" "INFO"
Check-SystemStatus
Update-Log "Hazır." "SUCCESS"

# --- ARAYÜZÜ BAŞLAT ---
$form.ShowDialog() | Out-Null