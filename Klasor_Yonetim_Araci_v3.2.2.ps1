<#
.SYNOPSIS
Çok Amaçlı Klasör Yönetim Aracı
Hazırlayan: Mehmet IŞIK
Güncelleme: v3.2.2 (Karakter Kodlaması ve Emoji Düzeltmesi)

.DEĞİŞİKLİK NOTLARI
- [v3.2.2] Dosya kodlaması UTF-8 with BOM (utf-8-sig) olarak ayarlandı. Windows PowerShell 5.1'in emojileri siyah-beyaz veya bozuk karakter (ANSI) olarak okuma sorunu kalıcı olarak çözüldü.
- [v3.2.1] JIT Hatası (Add_Paint op_Subtraction) düzeltildi. Arayüzdeki simgelerin (emojilerin) web/HTML ile birebir aynı renkli ve modern görünmesi için font "Segoe UI Emoji" olarak güncellendi.
- [v3.2.0] Arayüz tamamen yeniden tasarlandı.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.ComponentModel

# =========================================================
# UYGULAMA AYARLARI
# =========================================================
$ScriptVersion = "3.2.2"
$Config = @{
    Paths = @{
        ScanFolder     = "C:\Tarama"
        ShareFolder    = "C:\OrtakHavuz"
        LogFolder      = "$env:ProgramData\KlasorYonetim"
        SettingsFile   = "$env:ProgramData\KlasorYonetim\Settings.json"
        PowerBackup    = "$env:ProgramData\KlasorYonetim\power_backup.json"
        FirewallBackup = "$env:ProgramData\KlasorYonetim\Firewall_backup.json"
    }
    UI = @{
        FontName     = "Segoe UI Emoji"
        FontSize     = 9.5
        Margin       = 10
    }
    Log = @{
        MaxLines = 500
    }
    Password = @{
        DefaultLength = 12
        MinimumLength = 8
    }
}

# =========================================================
# GLOBAL UYGULAMA NESNESİ
# =========================================================
$App = @{
    Form         = $null
    Controls     = @{}
    LastPassword = $null
}

$script:OpStats = @{ Success = 0; Warning = 0; Error = 0 }

# =========================================================
# YÜKSEK ÇÖZÜNÜRLÜK (DPI) VE KONSOL GİZLEME
# =========================================================
$csharpCode = @"
using System;
using System.Runtime.InteropServices;
public static class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
Add-Type -TypeDefinition $csharpCode
[WinAPI]::SetProcessDPIAware() | Out-Null

$konsol = [WinAPI]::GetConsoleWindow()
if ($konsol -ne [IntPtr]::Zero) { [WinAPI]::ShowWindow($konsol, 0) | Out-Null }

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# =========================================================
# YÖNETİCİ (ADMIN) KONTROLÜ
# =========================================================
function Test-Admin {
    $currentUser = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $BetikYolu = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($BetikYolu)) { $BetikYolu = $MyInvocation.MyCommand.Path }

    try {
        if (-not [string]::IsNullOrWhiteSpace($BetikYolu) -and (Test-Path $BetikYolu)) {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$BetikYolu`""
            Start-Process powershell -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
        } else {
            $ScriptUrl = "https://raw.githubusercontent.com/mhmtsk44/Klasor-Yonetim-Araci/refs/heads/main/Klasor_Yonetim_Araci.ps1"
            $argList = "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$ScriptUrl' | iex`""
            Start-Process powershell -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Yönetici izni alınırken hata oluştu.", "Yönetici İzni Gerekli", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    exit
}

# =========================================================
# TEMEL MİMARİ FONKSİYONLARI
# =========================================================

function Ensure-Folder {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item $Path -ItemType Directory -Force | Out-Null
        Write-AppLog "$Path oluşturuldu." "INFO"
    }
}

function Write-AppLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Type = "INFO"
    )

    $time = Get-Date -Format "HH:mm:ss"
    
    switch ($Type) {
        "INFO"    { $Prefix = "[BİLGİ]" }
        "SUCCESS" { $Prefix = "[BAŞARILI]"; $script:OpStats.Success++ }
        "WARNING" { $Prefix = "[UYARI]";    $script:OpStats.Warning++ }
        "ERROR"   { $Prefix = "[HATA]";     $script:OpStats.Error++ }
    }

    $text = "[$time] $Prefix $Message"

    if ($App.Controls.LogTextBox) {
        $App.Controls.LogTextBox.AppendText($text + "`r`n")
        
        if ($App.Controls.LogTextBox.Lines.Count -gt $Config.Log.MaxLines) {
            $App.Controls.LogTextBox.Lines = $App.Controls.LogTextBox.Lines | Select-Object -Last $Config.Log.MaxLines
        }
        $App.Controls.LogTextBox.SelectionStart = $App.Controls.LogTextBox.TextLength
        $App.Controls.LogTextBox.ScrollToCaret()
    }

    Ensure-Folder $Config.Paths.LogFolder
    $logFile = Join-Path $Config.Paths.LogFolder "Program.log"
    Add-Content $logFile $text -Encoding UTF8

    try {
        $file = Get-Item $logFile -ErrorAction SilentlyContinue
        if ($file -and $file.Length -gt 1MB) {
            $lastLines = Get-Content $logFile -Tail $Config.Log.MaxLines
            Set-Content -Path $logFile -Value $lastLines -Encoding UTF8
        }
    } catch { }
}

function Save-Settings {
    Ensure-Folder $Config.Paths.LogFolder
    $Settings = @{ LastHost = $App.Controls.TxtHost.Text }
    $Settings | ConvertTo-Json | Set-Content $Config.Paths.SettingsFile -Encoding UTF8
}

function Load-Settings {
    if (Test-Path $Config.Paths.SettingsFile) {
        try {
            $Settings = Get-Content $Config.Paths.SettingsFile -Raw | ConvertFrom-Json
            if ($Settings.LastHost) { $App.Controls.TxtHost.Text = $Settings.LastHost }
        } catch { Write-AppLog "Ayarlar yüklenemedi: $($_.Exception.Message)" "WARNING" }
    }
}

function Invoke-WithProgress {
    param([string]$Title, [scriptblock]$Action)
    Write-AppLog $Title "INFO"
    $App.Controls.ProgressBar.Value = 0
    $App.Controls.ProgressBar.Visible = $true
    $App.Form.UseWaitCursor = $true
    $App.Form.Refresh()
    
    try { & $Action } 
    finally {
        $App.Controls.ProgressBar.Visible = $false
        $App.Controls.ProgressBar.Value = 0
        $App.Form.UseWaitCursor = $false
        $App.Form.Refresh()
    }
}

function Set-AppProgress { param([int]$Value); if ($App.Controls.ProgressBar) { $App.Controls.ProgressBar.Value = [math]::Min([math]::Max($Value, 0), 100); $App.Controls.ProgressBar.Refresh() } }

function Invoke-Safe {
    param([scriptblock]$Code)
    try { & $Code } 
    catch {
        Write-AppLog $_.Exception.Message "ERROR"
        if ($_.InvocationInfo) { Write-AppLog $_.InvocationInfo.PositionMessage "ERROR" }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Hata Oluştu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-OperationSummary {
    $msg = @"
İşlem tamamlandı! Olay Özeti:

Başarılı : $($script:OpStats.Success)
Uyarı    : $($script:OpStats.Warning)
Hata     : $($script:OpStats.Error)

Ayrıntılar için Logları kontrol edebilirsiniz.
"@
    [System.Windows.Forms.MessageBox]::Show($msg, "İşlem Tamamlandı", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $script:OpStats.Success = 0; $script:OpStats.Warning = 0; $script:OpStats.Error = 0
}

# =========================================================
# ALTYAPI FONKSİYONLARI
# =========================================================
function New-SafeSmbShare {
    param([string]$Name, [string]$Path, [string]$ChangeAccess, [string]$FullAccess)
    if (Get-Command New-SmbShare -ErrorAction SilentlyContinue) {
        $params = @{ Name = $Name; Path = $Path }
        if ($ChangeAccess) { $params.ChangeAccess = $ChangeAccess }
        if ($FullAccess) { $params.FullAccess = $FullAccess }
        New-SmbShare @params | Out-Null
        return
    }
    $cmd = "net share `"$Name`"=`"$Path`""
    if ($ChangeAccess) { $cmd += " /GRANT:`"$ChangeAccess`",CHANGE" }
    if ($FullAccess) { $cmd += " /GRANT:`"$FullAccess`",FULL" }
    cmd.exe /c $cmd | Out-Null
}

function Remove-OrtakErisimCredentials {
    try {
        $cmdkeyOutput = cmdkey /list | Out-String
        $target = ""
        foreach ($line in $cmdkeyOutput -split "`n") {
            if ($line -match "Target:\s*(.*)" -or $line -match "Hedef:\s*(.*)") { $target = $matches[1].Trim() }
            if ($line -match "OrtakErisim" -and $target) {
                cmdkey /delete:$target | Out-Null
                Write-AppLog "Kimlik bilgisi silindi : $target" "SUCCESS"
                $target = ""
            }
        }
    } catch { Write-AppLog "Credential silinemedi." "WARNING" }
}

function Remove-DesktopItems {
    $desktop = [Environment]::GetFolderPath("Desktop")
    @(
        "Tarama.lnk", 
        "OrtakHavuz.lnk", 
        "OrtakHavuz_Baglantisi.lnk", 
        "Ortak_Klasor_Baglanti_Bilgileri.txt",
        "Tarama_Ayar_Bilgileri.txt"
    ) | ForEach-Object {
        $item = Join-Path $desktop $_
        if (Test-Path $item) { 
            Remove-Item $item -Force 
            Write-AppLog "Masaüstünden silindi: $_" "SUCCESS"
        }
    }
}

function Test-PasswordComplexity {
    param([string]$Password, [string]$UserNameToAvoid = "")
    $result = [PSCustomObject]@{ IsValid = $true; Reasons = @() }
    if ($Password.Length -lt $Config.Password.MinimumLength) { $result.IsValid = $false; $result.Reasons += "en az $($Config.Password.MinimumLength) karakter olmalı" }
    $categoryCount = 0
    if ($Password -cmatch '[a-zçğıöşü]') { $categoryCount++ }
    if ($Password -cmatch '[A-ZÇĞIİÖŞÜ]') { $categoryCount++ }
    if ($Password -match '[0-9]') { $categoryCount++ }
    if ($Password -match '[^a-zA-Z0-9çğıöşüÇĞIİÖŞÜ]') { $categoryCount++ }
    if ($categoryCount -lt 3) { $result.IsValid = $false; $result.Reasons += "3 farklı kategori (büyük harf, küçük harf, rakam, simge) içermeli" }
    if ($UserNameToAvoid -and $Password.ToLower().Contains($UserNameToAvoid.ToLower())) { $result.IsValid = $false; $result.Reasons += "kullanıcı adını içeremez" }
    return $result
}

function Get-SecureRandomComplexPassword {
    $charsUpper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞIİÖŞÜ'
    $charsLower = 'abcdefghijklmnopqrstuvwxyzçğıöşü'
    $charsNum   = '0123456789'
    $charsSym   = '!@#$%&*'
    $allChars   = $charsUpper + $charsLower + $charsNum + $charsSym

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 14
        $rng.GetBytes($bytes) # ÖNCE doldur

        $passChars = @(
            $charsUpper[[int]$bytes[0]  % $charsUpper.Length],
            $charsUpper[[int]$bytes[1]  % $charsUpper.Length],
            $charsLower[[int]$bytes[2]  % $charsLower.Length],
            $charsLower[[int]$bytes[3]  % $charsLower.Length],
            $charsLower[[int]$bytes[4]  % $charsLower.Length],
            $charsLower[[int]$bytes[5]  % $charsLower.Length],
            $charsNum[[int]$bytes[6]    % $charsNum.Length],
            $charsNum[[int]$bytes[7]    % $charsNum.Length],
            $charsSym[[int]$bytes[8]    % $charsSym.Length],
            $charsSym[[int]$bytes[9]    % $charsSym.Length]
        )
        for ($i = 10; $i -lt 14; $i++) {
            $passChars += $allChars[[int]$bytes[$i] % $allChars.Length]
        }

        # Fisher-Yates ile kriptografik karıştırma
        $shuffleByte = New-Object byte[] 1
        for ($i = $passChars.Count - 1; $i -gt 0; $i--) {
            $rng.GetBytes($shuffleByte)
            $j = [int]$shuffleByte[0] % ($i + 1)
            $tmp = $passChars[$i]; $passChars[$i] = $passChars[$j]; $passChars[$j] = $tmp
        }
        return -join $passChars
    } finally {
        $rng.Dispose()
    }
}

function Show-PasswordInputDialog {
    param([string]$Prompt, [string]$UserNameToAvoid = "")

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Şifre Belirleyin"
    $dlg.Size = New-Object System.Drawing.Size(460, 380)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.Font = New-Object System.Drawing.Font($Config.UI.FontName, $Config.UI.FontSize)
    $dlg.BackColor = $UI.Bg

    # Üst başlık şeridi
    $dlgHeader = New-Object System.Windows.Forms.Panel
    $dlgHeader.Location = New-Object System.Drawing.Point(0, 0)
    $dlgHeader.Size = New-Object System.Drawing.Size(460, 46)
    $dlgHeader.BackColor = $UI.HeaderBg
    $dlg.Controls.Add($dlgHeader)

    $lblDlgTitle = New-Object System.Windows.Forms.Label
    $lblDlgTitle.Text = "🔐  Ağ Erişim Şifresi"
    $lblDlgTitle.Font = New-Object System.Drawing.Font($Config.UI.FontName, 11, [System.Drawing.FontStyle]::Bold)
    $lblDlgTitle.ForeColor = $UI.HeaderText
    $lblDlgTitle.Location = New-Object System.Drawing.Point(16, 11)
    $lblDlgTitle.AutoSize = $true
    $lblDlgTitle.UseCompatibleTextRendering = $false
    $dlgHeader.Controls.Add($lblDlgTitle)

    $lblPrompt = New-Object System.Windows.Forms.Label; $lblPrompt.Text = $Prompt; $lblPrompt.Location = New-Object System.Drawing.Point(18, 58); $lblPrompt.Size = New-Object System.Drawing.Size(410, 35); $lblPrompt.ForeColor = $UI.TextPrimary
    $lblHint = New-Object System.Windows.Forms.Label; $lblHint.Text = "ℹ️  Gereksinim: en az $($Config.Password.MinimumLength) karakter; karmaşık olmalı."; $lblHint.Location = New-Object System.Drawing.Point(18, 90); $lblHint.Size = New-Object System.Drawing.Size(410, 35); $lblHint.ForeColor = $UI.TextSecondary; $lblHint.UseCompatibleTextRendering = $false
    
    $lblPass = New-Object System.Windows.Forms.Label; $lblPass.Text = "Şifre:"; $lblPass.Location = New-Object System.Drawing.Point(18, 138); $lblPass.AutoSize = $true; $lblPass.ForeColor = $UI.TextPrimary
    $txtPassword = New-Object System.Windows.Forms.TextBox; $txtPassword.Location = New-Object System.Drawing.Point(138, 134); $txtPassword.Size = New-Object System.Drawing.Size(280, 26); $txtPassword.UseSystemPasswordChar = $true; $txtPassword.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    
    $lblConfirm = New-Object System.Windows.Forms.Label; $lblConfirm.Text = "Şifre (Tekrar):"; $lblConfirm.Location = New-Object System.Drawing.Point(18, 170); $lblConfirm.AutoSize = $true; $lblConfirm.ForeColor = $UI.TextPrimary
    $txtConfirm = New-Object System.Windows.Forms.TextBox; $txtConfirm.Location = New-Object System.Drawing.Point(138, 166); $txtConfirm.Size = New-Object System.Drawing.Size(280, 26); $txtConfirm.UseSystemPasswordChar = $true; $txtConfirm.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    
    $btnRandom = New-Object System.Windows.Forms.Button; $btnRandom.Text = "Rastgele Üret"; $btnRandom.Location = New-Object System.Drawing.Point(18, 200); $btnRandom.Size = New-Object System.Drawing.Size(135, 32)
    $btnRandom.FlatStyle = "Flat"; $btnRandom.BackColor = $UI.NeutralSoft; $btnRandom.ForeColor = $UI.NeutralText; $btnRandom.FlatAppearance.BorderColor = $UI.CardBorder; $btnRandom.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnRandom.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(210, 224, 250); $btnRandom.UseCompatibleTextRendering = $false

    $chkShow = New-Object System.Windows.Forms.CheckBox; $chkShow.Text = "Şifreyi göster"; $chkShow.Location = New-Object System.Drawing.Point(165, 206); $chkShow.AutoSize = $true; $chkShow.ForeColor = $UI.TextSecondary
    $lblError = New-Object System.Windows.Forms.Label; $lblError.Location = New-Object System.Drawing.Point(18, 240); $lblError.Size = New-Object System.Drawing.Size(410, 35); $lblError.ForeColor = $UI.DangerText
    
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = "Tamam"; $btnOk.Location = New-Object System.Drawing.Point(228, 282); $btnOk.Size = New-Object System.Drawing.Size(100, 34)
    $btnOk.FlatStyle = "Flat"; $btnOk.BackColor = $UI.AccentPrimary; $btnOk.ForeColor = [System.Drawing.Color]::White; $btnOk.Font = New-Object System.Drawing.Font($Config.UI.FontName, $Config.UI.FontSize, [System.Drawing.FontStyle]::Bold)
    $btnOk.FlatAppearance.BorderSize = 0; $btnOk.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnOk.FlatAppearance.MouseOverBackColor = $UI.AccentPrimaryDark

    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "İptal"; $btnCancel.Location = New-Object System.Drawing.Point(334, 282); $btnCancel.Size = New-Object System.Drawing.Size(100, 34)
    $btnCancel.FlatStyle = "Flat"; $btnCancel.BackColor = [System.Drawing.Color]::White; $btnCancel.ForeColor = $UI.TextPrimary
    $btnCancel.FlatAppearance.BorderColor = $UI.CardBorder; $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.FlatAppearance.MouseOverBackColor = $UI.Bg

    $dlg.Controls.AddRange(@($lblPrompt, $lblHint, $lblPass, $txtPassword, $lblConfirm, $txtConfirm, $btnRandom, $chkShow, $lblError, $btnOk, $btnCancel))

    $chkShow.Add_CheckedChanged({ $txtPassword.UseSystemPasswordChar = -not $chkShow.Checked; $txtConfirm.UseSystemPasswordChar = -not $chkShow.Checked })
    $btnRandom.Add_Click({ $newPass = Get-SecureRandomComplexPassword; $txtPassword.Text = $newPass; $txtConfirm.Text = $newPass; $chkShow.Checked = $true })

    $txtPassword.Add_TextChanged({ $lblError.Text = "" })
    $txtConfirm.Add_TextChanged({ $lblError.Text = "" })

    $script:DialogResultPass = $null
    $btnOk.Add_Click({
        if ($txtPassword.Text -ne $txtConfirm.Text) { $lblError.Text = "Girilen şifreler eşleşmiyor."; return }
        $check = Test-PasswordComplexity -Password $txtPassword.Text -UserNameToAvoid $UserNameToAvoid
        if (-not $check.IsValid) { $lblError.Text = "Şifre kabul edilmedi: " + ($check.Reasons -join "; "); return }
        $script:DialogResultPass = $txtPassword.Text; $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    [void]$dlg.ShowDialog()
    return $script:DialogResultPass
}

function Test-NetworkSharing {
    Write-AppLog "SMB servisi kontrol ediliyor..." "INFO"
    $Service = Get-Service LanmanServer -ErrorAction SilentlyContinue
    if ($Service) {
        if ($Service.StartType -ne "Automatic") { Set-Service -Name LanmanServer -StartupType Automatic; Write-AppLog "SMB servisinin başlangıç türü Otomatik olarak ayarlandı." "SUCCESS" }
        if ($Service.Status -ne "Running") { Start-Service LanmanServer }
    }
}

function Backup-PowerSettingsIfNeeded {
    if (Test-Path $Config.Paths.PowerBackup) { return }
    Ensure-Folder $Config.Paths.LogFolder
    try {
        function Get-PowerSettingValues {
            param([string]$SubCommand)
            $output = powercfg /query SCHEME_CURRENT SUB_SLEEP $SubCommand 2>$null
            $acValue = $null
            $dcValue = $null
            foreach ($line in $output) {
                if ($line -match "AC.*:\s*(0x[0-9a-fA-F]+)") {
                    $acValue = [Convert]::ToInt32($matches[1], 16)
                }
                elseif ($line -match "DC.*:\s*(0x[0-9a-fA-F]+)") {
                    $dcValue = [Convert]::ToInt32($matches[1], 16)
                }
            }
            return [PSCustomObject]@{
                AC = $acValue
                DC = $dcValue
            }
        }

        $standby = Get-PowerSettingValues "STANDBYIDLE"
        $hibernate = Get-PowerSettingValues "HIBERNATEIDLE"

        $backup = [PSCustomObject]@{
            StandbyAC   = $standby.AC
            StandbyDC   = $standby.DC
            HibernateAC = $hibernate.AC
            HibernateDC = $hibernate.DC
        }
        $backup | ConvertTo-Json | Set-Content -Path $Config.Paths.PowerBackup -Encoding UTF8
        Write-AppLog "Orijinal güç ayarları (AC/DC) yedeklendi." "INFO"
    } catch { Write-AppLog $_.Exception.Message "ERROR" }
}

function Disable-SleepMode {
    Write-AppLog "Güç ayarları optimize ediliyor (Uyku Modu Kapatılıyor)..." "INFO"
    Backup-PowerSettingsIfNeeded
    powercfg.exe /change standby-timeout-ac 0
    powercfg.exe /change standby-timeout-dc 0
    powercfg.exe /change hibernate-timeout-ac 0
    powercfg.exe /change hibernate-timeout-dc 0
    Write-AppLog "Güç ayarları güncellendi." "SUCCESS"
}

function Restore-PowerSettings {
    if (-not (Test-Path $Config.Paths.PowerBackup)) { return }
    try {
        $backup = Get-Content $Config.Paths.PowerBackup -Raw | ConvertFrom-Json
        if ($null -ne $backup.StandbyAC)   { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $backup.StandbyAC }
        if ($null -ne $backup.StandbyDC)   { powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $backup.StandbyDC }
        if ($null -ne $backup.HibernateAC) { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE $backup.HibernateAC }
        if ($null -ne $backup.HibernateDC) { powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE $backup.HibernateDC }
        powercfg /setactive SCHEME_CURRENT
        Remove-Item $Config.Paths.PowerBackup -Force -ErrorAction SilentlyContinue
        Write-AppLog "Güç ayarları geri yüklendi." "SUCCESS"
    } catch { Write-AppLog $_.Exception.Message "ERROR" }
}

function Enable-SharingFirewallGroup {
    param([string]$GroupNameEn, [string]$GroupNameTr)
    Ensure-Folder $Config.Paths.LogFolder
    $wasAlreadyEnabled = $false
    try {
        $rules = Get-NetFirewallRule -DisplayGroup $GroupNameEn -ErrorAction Stop
        $wasAlreadyEnabled = ($rules | Where-Object { $_.Enabled -eq "True" }).Count -eq $rules.Count -and $rules.Count -gt 0
        Enable-NetFirewallRule -DisplayGroup $GroupNameEn -ErrorAction Stop
    } catch { netsh advfirewall firewall set rule group="$GroupNameTr" new enable=Yes | Out-Null }
    
    $backup = @{}
    if (Test-Path $Config.Paths.FirewallBackup) {
        $json = Get-Content $Config.Paths.FirewallBackup -Raw | ConvertFrom-Json
        if ($json) { foreach ($prop in $json.psobject.properties) { $backup[$prop.Name] = $prop.Value } }
    }
    if (-not $backup.ContainsKey($GroupNameEn)) { $backup[$GroupNameEn] = -not $wasAlreadyEnabled }
    $backup | ConvertTo-Json | Set-Content -Path $Config.Paths.FirewallBackup -Encoding UTF8
}

function Restore-SharingFirewallGroups {
    if (-not (Test-Path $Config.Paths.FirewallBackup)) { return }
    try {
        $json = Get-Content $Config.Paths.FirewallBackup -Raw | ConvertFrom-Json
        if ($json) {
            foreach ($prop in $json.psobject.properties) {
                $group = $prop.Name; $value = $prop.Value
                if ($value -eq $true) {
                    try { Disable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop } 
                    catch {
                        $trGroup = $group
                        if ($group -eq "File and Printer Sharing") { $trGroup = "Dosya ve Yazıcı Paylaşımı" }
                        if ($group -eq "Network Discovery") { $trGroup = "Ağ Bulma" }
                        netsh advfirewall firewall set rule group="$trGroup" new enable=No | Out-Null
                    }
                    Write-AppLog "'$group' kuralı geri alındı." "SUCCESS"
                }
            }
        }
        Remove-Item $Config.Paths.FirewallBackup -Force -ErrorAction SilentlyContinue
    } catch { Write-AppLog $_.Exception.Message "ERROR" }
}

function New-DesktopShortcut {
    param([string]$ShortcutName, [string]$TargetPath)
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $ShortcutPath = Join-Path $DesktopPath "$ShortcutName.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath); $Shortcut.TargetPath = $TargetPath; $Shortcut.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WScriptShell)
    Write-AppLog "Masaüstüne '$ShortcutName' eklendi." "SUCCESS"
}

# =========================================================
# KURUMSAL RENK PALETİ VE ARAYÜZ YARDIMCI FONKSİYONLARI
# =========================================================
$UI = @{
    Bg                = [System.Drawing.Color]::FromArgb(241, 244, 249)
    HeaderBg          = [System.Drawing.Color]::FromArgb(24, 38, 66)
    HeaderText        = [System.Drawing.Color]::White
    HeaderSubText     = [System.Drawing.Color]::FromArgb(163, 176, 204)
    CardBg            = [System.Drawing.Color]::White
    CardBorder        = [System.Drawing.Color]::FromArgb(224, 228, 237)
    AccentPrimary     = [System.Drawing.Color]::FromArgb(46, 90, 172)
    AccentPrimaryDark = [System.Drawing.Color]::FromArgb(30, 64, 130)
    TextPrimary       = [System.Drawing.Color]::FromArgb(31, 41, 55)
    TextSecondary     = [System.Drawing.Color]::FromArgb(107, 114, 128)
    SuccessSoft       = [System.Drawing.Color]::FromArgb(228, 246, 235)
    SuccessText       = [System.Drawing.Color]::FromArgb(27, 110, 60)
    WarnSoft          = [System.Drawing.Color]::FromArgb(255, 243, 220)
    WarnText          = [System.Drawing.Color]::FromArgb(150, 90, 10)
    DangerSoft        = [System.Drawing.Color]::FromArgb(253, 232, 232)
    DangerSolid       = [System.Drawing.Color]::FromArgb(196, 58, 58)
    DangerText        = [System.Drawing.Color]::FromArgb(176, 42, 42)
    NeutralSoft       = [System.Drawing.Color]::FromArgb(232, 240, 254)
    NeutralText       = [System.Drawing.Color]::FromArgb(30, 64, 120)
    LogBg             = [System.Drawing.Color]::FromArgb(28, 32, 44)
    LogText           = [System.Drawing.Color]::FromArgb(210, 218, 230)
}

function New-Card {
    param(
        [string]$Title,
        [string]$Icon = "",
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Windows.Forms.Control]$Parent
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = $Location
    $panel.Size = $Size
    $panel.BackColor = $UI.CardBg

    $panel.Add_Paint({
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
        $pen = New-Object System.Drawing.Pen($UI.CardBorder, 1)
        $_.Graphics.DrawRectangle($pen, $rect)
        $pen.Dispose()
    })

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$Icon  $Title"
    $lblTitle.Font = New-Object System.Drawing.Font($Config.UI.FontName, 9.5, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $UI.AccentPrimaryDark
    $lblTitle.Location = New-Object System.Drawing.Point(14, 9)
    $lblTitle.AutoSize = $true
    $lblTitle.UseCompatibleTextRendering = $false
    $panel.Controls.Add($lblTitle)

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Location = New-Object System.Drawing.Point(14, 31)
    $sep.Size = New-Object System.Drawing.Size(($Size.Width - 28), 1)
    $sep.BackColor = $UI.CardBorder
    $panel.Controls.Add($sep)

    if ($Parent) { $Parent.Controls.Add($panel) }
    return $panel
}

function New-StyledButton {
    param(
        [string]$Text,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Drawing.Color]$BackColor,
        [System.Drawing.Color]$ForeColor = $UI.TextPrimary,
        [switch]$Bold,
        [switch]$Solid,
        [System.Windows.Forms.Control]$Parent
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = $Location
    $btn.Size = $Size
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = $(if ($Solid) { 0 } else { 1 })
    $btn.FlatAppearance.BorderColor = $UI.CardBorder
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $btn.UseCompatibleTextRendering = $false

    $fontStyle = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $btn.Font = New-Object System.Drawing.Font($Config.UI.FontName, $Config.UI.FontSize, $fontStyle)

    $btn.Add_MouseEnter({
        $cur = $this.BackColor
        $this.Tag = $cur
        $r = [Math]::Max(0, [int]$cur.R - 14); $g = [Math]::Max(0, [int]$cur.G - 14); $b = [Math]::Max(0, [int]$cur.B - 14)
        $this.BackColor = [System.Drawing.Color]::FromArgb($r, $g, $b)
    })
    $btn.Add_MouseLeave({
        if ($this.Tag -is [System.Drawing.Color]) { $this.BackColor = $this.Tag }
    })

    if ($Parent) { $Parent.Controls.Add($btn) }
    return $btn
}

# =========================================================
# ARAYÜZ (FORM) TANIMLAMALARI (KURUMSAL KART TASARIMI)
# =========================================================

$App.Form = New-Object System.Windows.Forms.Form
$App.Form.Text = "Çok Amaçlı Klasör Yönetim Aracı v$ScriptVersion"
$App.Form.Size = New-Object System.Drawing.Size(780, 758)
$App.Form.StartPosition = "CenterScreen"
$App.Form.FormBorderStyle = "FixedDialog"
$App.Form.MaximizeBox = $false
$App.Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$App.Form.Font = New-Object System.Drawing.Font($Config.UI.FontName, $Config.UI.FontSize)
$App.Form.BackColor = $UI.Bg

$iconPath = Join-Path $PSScriptRoot "KlasorYonetim.ico"
if (-not (Test-Path $iconPath)) { $iconPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "KlasorYonetim.ico" }
if (Test-Path $iconPath) {
    $App.Form.Icon = New-Object System.Drawing.Icon($iconPath)
}

# --- ÜST BAŞLIK ÇUBUĞU ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size = New-Object System.Drawing.Size(780, 64)
$pnlHeader.BackColor = $UI.HeaderBg
$App.Form.Controls.Add($pnlHeader)

$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = "📁  Çok Amaçlı Klasör Yönetim Aracı"
$lblAppTitle.Font = New-Object System.Drawing.Font($Config.UI.FontName, 13, [System.Drawing.FontStyle]::Bold)
$lblAppTitle.ForeColor = $UI.HeaderText
$lblAppTitle.Location = New-Object System.Drawing.Point(20, 10)
$lblAppTitle.AutoSize = $true
$lblAppTitle.UseCompatibleTextRendering = $false
$pnlHeader.Controls.Add($lblAppTitle)

$lblAppSubtitle = New-Object System.Windows.Forms.Label
$lblAppSubtitle.Text = "v$ScriptVersion   •   Yönetici Modu Aktif   •   $env:COMPUTERNAME"
$lblAppSubtitle.Font = New-Object System.Drawing.Font($Config.UI.FontName, 9)
$lblAppSubtitle.ForeColor = $UI.HeaderSubText
$lblAppSubtitle.Location = New-Object System.Drawing.Point(22, 38)
$lblAppSubtitle.AutoSize = $true
$lblAppSubtitle.UseCompatibleTextRendering = $false
$pnlHeader.Controls.Add($lblAppSubtitle)

# ANA SEKMELER
$App.Controls.TabControl = New-Object System.Windows.Forms.TabControl
$App.Controls.TabControl.Size = New-Object System.Drawing.Size(744, 240)
$App.Controls.TabControl.Location = New-Object System.Drawing.Point(18, 78)
$App.Controls.TabControl.Font = New-Object System.Drawing.Font($Config.UI.FontName, 9.5)
$App.Form.Controls.Add($App.Controls.TabControl)

# ALT KISIM: LOG VE DURUM KARTI
$gbLog = New-Card -Title "İşlem Durumu ve Sistem Kayıtları (Log)" -Icon "🖥️" -Location (New-Object System.Drawing.Point(18, 328)) -Size (New-Object System.Drawing.Size(744, 320)) -Parent $App.Form

$App.Controls.ProgressBar = New-Object System.Windows.Forms.ProgressBar
$App.Controls.ProgressBar.Location = New-Object System.Drawing.Point(14, 42)
$App.Controls.ProgressBar.Size = New-Object System.Drawing.Size(716, 16)
$App.Controls.ProgressBar.Visible = $false
$App.Controls.ProgressBar.Style = "Continuous"
$gbLog.Controls.Add($App.Controls.ProgressBar)

$App.Controls.LogTextBox = New-Object System.Windows.Forms.TextBox
$App.Controls.LogTextBox.Multiline = $true
$App.Controls.LogTextBox.ScrollBars = "Vertical"
$App.Controls.LogTextBox.Size = New-Object System.Drawing.Size(716, 258)
$App.Controls.LogTextBox.Location = New-Object System.Drawing.Point(14, 46)
$App.Controls.LogTextBox.ReadOnly = $true
$App.Controls.LogTextBox.BackColor = $UI.LogBg
$App.Controls.LogTextBox.ForeColor = $UI.LogText
$App.Controls.LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$App.Controls.LogTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$gbLog.Controls.Add($App.Controls.LogTextBox)

# --- ALT DURUM ÇUBUĞU ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.BackColor = $UI.Bg
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Hazır  •  Kullanıcı: $env:USERNAME"
$statusLabel.ForeColor = $UI.TextSecondary
[void]$statusStrip.Items.Add($statusLabel)

$signatureLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$signatureLabel.Text = "Mehmet IŞIK"
$signatureLabel.Font = New-Object System.Drawing.Font($Config.UI.FontName, 8.5, [System.Drawing.FontStyle]::Italic)
$signatureLabel.ForeColor = [System.Drawing.Color]::FromArgb(160, 168, 184)
$signatureLabel.Alignment = [System.Windows.Forms.ToolStripItemAlignment]::Right
[void]$statusStrip.Items.Add($signatureLabel)

$App.Form.Controls.Add($statusStrip)

# --- SEKME 1: TARAMA KLASÖRÜ ---
$App.Controls.TabScan = New-Object System.Windows.Forms.TabPage; $App.Controls.TabScan.Text = "1. Tarama Klasörü"; $App.Controls.TabScan.BackColor = $UI.Bg
$App.Controls.TabControl.TabPages.Add($App.Controls.TabScan)

$gbScanMain = New-Card -Title "Ağ Üzerinden Tarama Altyapısı" -Icon "🖨️" -Location (New-Object System.Drawing.Point(14, 10)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabScan

$App.Controls.BtnScan = New-StyledButton -Text "Tarama Klasörünü Kur ($($Config.Paths.ScanFolder))" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(676, 42)) -BackColor ([System.Drawing.Color]::LightGoldenrodYellow) -Bold -Parent $gbScanMain

$gbScanSmb = New-Card -Title "Eski Nesil Tarayıcılar İçin Güvenlik Ayarları" -Icon "⚙️" -Location (New-Object System.Drawing.Point(14, 108)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabScan

$App.Controls.BtnSmb1 = New-StyledButton -Text "SMB 1.0 Aç (Önerilmez)" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.DangerSoft -ForeColor $UI.DangerText -Bold -Parent $gbScanSmb
$App.Controls.BtnSmb1Disable = New-StyledButton -Text "SMB 1.0 Kapat (Güvenli)" -Location (New-Object System.Drawing.Point(360, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.SuccessSoft -ForeColor $UI.SuccessText -Parent $gbScanSmb

# --- SEKME 2: ORTAK ÇALIŞMA KLASÖRÜ ---
$App.Controls.TabHost = New-Object System.Windows.Forms.TabPage; $App.Controls.TabHost.Text = "2. Ortak Klasör (Ana PC)"; $App.Controls.TabHost.BackColor = $UI.Bg
$App.Controls.TabControl.TabPages.Add($App.Controls.TabHost)

$gbHostMain = New-Card -Title "Sunucu (Host) Yapılandırması" -Icon "🗄️" -Location (New-Object System.Drawing.Point(14, 10)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabHost

$App.Controls.BtnHost = New-StyledButton -Text "Ortak Havuz Altyapısını Kur ($($Config.Paths.ShareFolder))" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(676, 42)) -BackColor ([System.Drawing.Color]::Honeydew) -Bold -Parent $gbHostMain

$gbHostInfo = New-Card -Title "Bağlantı Bilgileri Dağıtımı (Bu Oturuma Özel)" -Icon "🔑" -Location (New-Object System.Drawing.Point(14, 108)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabHost

$App.Controls.BtnCopyPC = New-StyledButton -Text "🖥️ Bilgisayar Adını Kopyala" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.NeutralSoft -ForeColor $UI.NeutralText -Parent $gbHostInfo
$App.Controls.BtnCopyPass = New-StyledButton -Text "🔑 Son Şifreyi Kopyala" -Location (New-Object System.Drawing.Point(360, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.NeutralSoft -ForeColor $UI.NeutralText -Parent $gbHostInfo

# --- SEKME 3: DİĞER PC'DEN BAĞLAN ---
$App.Controls.TabClient = New-Object System.Windows.Forms.TabPage; $App.Controls.TabClient.Text = "3. Diğer PC'den Bağlan"; $App.Controls.TabClient.BackColor = $UI.Bg
$App.Controls.TabControl.TabPages.Add($App.Controls.TabClient)

$gbClientConfig = New-Card -Title "Ana Bilgisayara (Host) Bağlantı" -Icon "🌐" -Location (New-Object System.Drawing.Point(14, 10)) -Size (New-Object System.Drawing.Size(704, 188)) -Parent $App.Controls.TabClient

$App.Controls.LblHost = New-Object System.Windows.Forms.Label; $App.Controls.LblHost.Text = "Ana Bilgisayarın Adı:"; $App.Controls.LblHost.Location = New-Object System.Drawing.Point(18, 48); $App.Controls.LblHost.AutoSize = $true; $App.Controls.LblHost.ForeColor = $UI.TextPrimary
$App.Controls.TxtHost = New-Object System.Windows.Forms.TextBox; $App.Controls.TxtHost.Location = New-Object System.Drawing.Point(190, 44); $App.Controls.TxtHost.Size = New-Object System.Drawing.Size(490, 26); $App.Controls.TxtHost.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$App.Controls.LblPass = New-Object System.Windows.Forms.Label; $App.Controls.LblPass.Text = "OrtakErisim Şifresi:"; $App.Controls.LblPass.Location = New-Object System.Drawing.Point(18, 88); $App.Controls.LblPass.AutoSize = $true; $App.Controls.LblPass.ForeColor = $UI.TextPrimary
$App.Controls.TxtPass = New-Object System.Windows.Forms.TextBox; $App.Controls.TxtPass.Location = New-Object System.Drawing.Point(190, 84); $App.Controls.TxtPass.Size = New-Object System.Drawing.Size(490, 26); $App.Controls.TxtPass.UseSystemPasswordChar = $true; $App.Controls.TxtPass.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$App.Controls.BtnClient = New-StyledButton -Text "🔗 Ortak Havuza Güvenli Bağlan" -Location (New-Object System.Drawing.Point(190, 126)) -Size (New-Object System.Drawing.Size(490, 44)) -BackColor $UI.AccentPrimary -ForeColor ([System.Drawing.Color]::White) -Bold -Solid -Parent $gbClientConfig

$gbClientConfig.Controls.AddRange(@($App.Controls.LblHost, $App.Controls.TxtHost, $App.Controls.LblPass, $App.Controls.TxtPass))

# --- SEKME 4: SİSTEMİ KALDIR ---
$App.Controls.TabRemove = New-Object System.Windows.Forms.TabPage; $App.Controls.TabRemove.Text = "4. Kurulumu Kaldır"; $App.Controls.TabRemove.BackColor = $UI.Bg
$App.Controls.TabControl.TabPages.Add($App.Controls.TabRemove)

$gbRemoveSelect = New-Card -Title "Seçmeli Kaldırma (Sadece İlgili Bölümü Siler)" -Icon "🧹" -Location (New-Object System.Drawing.Point(14, 10)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabRemove

$App.Controls.BtnRemoveTarama = New-StyledButton -Text "Tarama Klasörünü Kaldır" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.WarnSoft -ForeColor $UI.WarnText -Parent $gbRemoveSelect
$App.Controls.BtnRemoveOrtak = New-StyledButton -Text "Ortak Havuzu Kaldır" -Location (New-Object System.Drawing.Point(360, 40)) -Size (New-Object System.Drawing.Size(330, 42)) -BackColor $UI.WarnSoft -ForeColor $UI.WarnText -Parent $gbRemoveSelect

$gbRemoveAll = New-Card -Title "Tam Temizlik (Önerilen)" -Icon "🗑️" -Location (New-Object System.Drawing.Point(14, 108)) -Size (New-Object System.Drawing.Size(704, 90)) -Parent $App.Controls.TabRemove

$App.Controls.BtnRemoveAll = New-StyledButton -Text "Sistemi Orijinal Haline Döndür ve Tamamen Temizle" -Location (New-Object System.Drawing.Point(14, 40)) -Size (New-Object System.Drawing.Size(676, 42)) -BackColor $UI.DangerSolid -ForeColor ([System.Drawing.Color]::White) -Bold -Solid -Parent $gbRemoveAll


# =========================================================
# İŞLEM (ACTION) FONKSİYONLARI
# =========================================================

function Start-ScanSetup {
    Invoke-Safe {
        Invoke-WithProgress "Tarayıcı kuruluyor..." {
            Test-NetworkSharing; Set-AppProgress 15
            Disable-SleepMode; Set-AppProgress 30
            Enable-SharingFirewallGroup "File and Printer Sharing" "Dosya ve Yazıcı Paylaşımı"
            Enable-SharingFirewallGroup "Network Discovery" "Ağ Bulma"
            Set-AppProgress 45

            Ensure-Folder $Config.Paths.ScanFolder; Set-AppProgress 60

            $ShareName = "Tarama`$"
            if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
                New-SafeSmbShare -Name $ShareName -Path $Config.Paths.ScanFolder -ChangeAccess Everyone
                Write-AppLog "Klasör ağa gizli ($ShareName) olarak paylaşıldı." "SUCCESS"
            }
            Set-AppProgress 75

            $Acl = Get-Acl -Path $Config.Paths.ScanFolder
            $ident = "$env:COMPUTERNAME\$env:USERNAME"
            if (-not ($Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident -and $_.FileSystemRights.HasFlag([System.Security.AccessControl.FileSystemRights]::FullControl) })) {
                $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ($ident, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
                Set-Acl -Path $Config.Paths.ScanFolder -AclObject $Acl
                Write-AppLog "Klasör izinleri (ACL) uygulandı." "SUCCESS"
            }
            Set-AppProgress 90

            New-DesktopShortcut -ShortcutName "Tarama" -TargetPath $Config.Paths.ScanFolder
            Start-Process explorer.exe $Config.Paths.ScanFolder
            
            $App.Controls.BtnScan.Text = "Tarama Klasörü Zaten Kurulu ($($Config.Paths.ScanFolder))"
            $App.Controls.BtnScan.BackColor = [System.Drawing.Color]::WhiteSmoke
            
            Set-AppProgress 100
            Write-AppLog "TARAMA İŞLEMİ TAMAMLANDI!" "SUCCESS"
            
            Show-OperationSummary
            
            $fullPath = "\$env:COMPUTERNAME\$ShareName"

            $txtContent = "--- YAZICI / FOTOKOPİ TARAMA AYAR BİLGİLERİ ---`r`n" +
                          "Paylaşım Adı: $ShareName`r`n" +
                          "Tam Yol (Full Path): $fullPath`r`n" +
                          "   (Not: Makineniz hangisini destekliyorsa onu kullanın)`r`n`r`n" +
                          "Kullanıcı Adı: $env:COMPUTERNAME\$env:USERNAME`r`n" +
                          "   >>> NOT: Eğer makinede ayrı bir 'Etki Alanı (Domain)' kutusu varsa;`r`n" +
                          "       Domain: $env:COMPUTERNAME`r`n" +
                          "       Kullanıcı Adı: $env:USERNAME olarak ayırarak yazınız.`r`n`r`n" +
                          "Şifre: (Bilgisayarı açarken kullandığınız kendi şifreniz)`r`n`r`n" +
                          "DİKKAT: Klasör gizli paylaşıldığı için yol kısmının sonundaki '$' işaretini mutlaka yazın."
            
            $txtPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "Tarama_Ayar_Bilgileri.txt"
            Set-Content -Path $txtPath -Value $txtContent -Encoding UTF8
            Write-AppLog "Tarama ayar bilgileri masaüstüne txt olarak otomatik kaydedildi." "SUCCESS"

            $infoMsg = "Tarama altyapısı başarıyla oluşturuldu!`n`n" +
                       "Yazıcı veya fotokopi makinenizin web arayüzüne/paneline ayarları girerken şu bilgileri kullanmalısınız:`n`n" +
                       "📌 Paylaşım Adı: $ShareName`n" +
                       "📌 Tam Yol (Full Path): $fullPath`n" +
                       "   (Not: Bazı yazıcılar sadece paylaşım adını, bazıları ise tam yolu ister.)`n`n" +
                       "👤 Kullanıcı Adı: $env:COMPUTERNAME\$env:USERNAME`n" +
                       "   💡 ÖNEMLİ: Eğer yazıcıda 'Etki Alanı (Domain)' diye ayrı bir kutu varsa;`n" +
                       "      Domain kısmına: $env:COMPUTERNAME`n" +
                       "      Kullanıcı Adı kısmına: $env:USERNAME yazınız.`n`n" +
                       "🔑 Şifre: (Bilgisayarı açarken kullandığınız kendi şifreniz)`n`n" +
                       "DİKKAT: Klasör gizli paylaşıldığı için yol kısmının sonundaki '$' işaretini mutlaka yazmayı unutmayın.`n`n" +
                       "✅ Bu bilgiler masaüstünüze 'Tarama_Ayar_Bilgileri.txt' olarak otomatik kaydedilmiştir."
            
            [System.Windows.Forms.MessageBox]::Show($infoMsg, "Yazıcı Ayar Bilgileri", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    }
}

function Start-Smb1Enable {
    Invoke-Safe {
        if ([System.Windows.Forms.MessageBox]::Show("DİKKAT: SMB 1.0 çok eski ve güvenlik açığı barındırır... Onaylıyor musunuz?", "Uyarı", "YesNo", "Warning") -eq 'Yes') {
            Invoke-WithProgress "SMB 1.0 aktifleştiriliyor..." {
                Enable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -All -NoRestart -ErrorAction Stop | Out-Null
                Write-AppLog "SMB 1.0 başarıyla açıldı." "SUCCESS"
                [System.Windows.Forms.MessageBox]::Show("SMB 1.0 açıldı.`n`nYENİDEN BAŞLATIN.", "Başarılı", "OK", "Information")
            }
        }
    }
}

function Start-Smb1Disable {
    Invoke-Safe {
        if ([System.Windows.Forms.MessageBox]::Show("SMB 1.0 tamamen devre dışı bırakılacak... Onaylıyor musunuz?", "Onay", "YesNo", "Question") -eq 'Yes') {
            Invoke-WithProgress "SMB 1.0 devre dışı bırakılıyor..." {
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction Stop | Out-Null
                Write-AppLog "SMB 1.0 başarıyla kapatıldı." "SUCCESS"
                [System.Windows.Forms.MessageBox]::Show("SMB 1.0 kapatıldı.`n`nYENİDEN BAŞLATIN.", "Başarılı", "OK", "Information")
            }
        }
    }
}

function Start-HostSetup {
    Invoke-Safe {
        $ShareName = "OrtakHavuz"; $OrtakUser = "OrtakErisim"; $AdminUser = $env:USERNAME
        $accountCreated = $false; $plainPassword = $null
        
        if (-not (Get-LocalUser -Name $OrtakUser -ErrorAction SilentlyContinue)) {
            $promptText = "'$OrtakUser' ağ erişim hesabı için bir şifre belirleyin:"
            while ($true) {
                $plainPassword = Show-PasswordInputDialog -Prompt $promptText -UserNameToAvoid $OrtakUser
                if (-not $plainPassword) { Write-AppLog "Şifre girilmediği için işlem iptal edildi." "WARNING"; return }
                
                try {
                    $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
                    New-LocalUser -Name $OrtakUser -Password $securePassword -Description "Ağ ortak erişim hesabı" -ErrorAction Stop | Out-Null
                    Set-LocalUser -Name $OrtakUser -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                    
                    $accountCreated = $true
                    Write-AppLog "'$OrtakUser' hesabı oluşturuldu." "SUCCESS"
                    break
                } catch {
                    Write-AppLog "Windows güvenlik politikası şifreyi reddetti: $($_.Exception.Message)" "WARNING"
                    $promptText = "Windows politikası şifreyi reddetti. Lütfen farklı bir şifre girin:"
                }
            }
        }

        Invoke-WithProgress "Ortak Havuz altyapısı kuruluyor..." {
            Test-NetworkSharing; Set-AppProgress 20
            Disable-SleepMode; Set-AppProgress 40
            Enable-SharingFirewallGroup "File and Printer Sharing" "Dosya ve Yazıcı Paylaşımı"; Set-AppProgress 60
            Ensure-Folder $Config.Paths.ShareFolder

            if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
                New-SafeSmbShare -Name $ShareName -Path $Config.Paths.ShareFolder -ChangeAccess "$env:COMPUTERNAME\$OrtakUser" -FullAccess "$env:COMPUTERNAME\$AdminUser"
            } else {
                Grant-SmbShareAccess -Name $ShareName -AccountName "$env:COMPUTERNAME\$OrtakUser" -AccessRight Change -Force -ErrorAction SilentlyContinue | Out-Null
                Grant-SmbShareAccess -Name $ShareName -AccountName "$env:COMPUTERNAME\$AdminUser" -AccessRight Full -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-AppProgress 80

            $Acl = Get-Acl -Path $Config.Paths.ShareFolder
            $ident1 = "$env:COMPUTERNAME\$OrtakUser"; $ident2 = "$env:COMPUTERNAME\$AdminUser"
            if (-not ($Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident1 -and $_.FileSystemRights.HasFlag([System.Security.AccessControl.FileSystemRights]::Modify) })) {
                $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ($ident1, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
            }
            if (-not ($Acl.Access | Where-Object { $_.IdentityReference.Value -eq $ident2 -and $_.FileSystemRights.HasFlag([System.Security.AccessControl.FileSystemRights]::FullControl) })) {
                $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ($ident2, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
            }
            Set-Acl -Path $Config.Paths.ShareFolder -AclObject $Acl
            
            New-DesktopShortcut -ShortcutName "OrtakHavuz" -TargetPath $Config.Paths.ShareFolder
            Start-Process explorer.exe $Config.Paths.ShareFolder
            
            $App.Controls.BtnHost.Text = "Ortak Havuz Zaten Kurulu ($($Config.Paths.ShareFolder))"
            $App.Controls.BtnHost.BackColor = [System.Drawing.Color]::WhiteSmoke
            
            Set-AppProgress 100
            Write-AppLog "ORTAK HAVUZ İŞLEMİ TAMAMLANDI!" "SUCCESS"

            if ($accountCreated) {
                Set-Clipboard $plainPassword
                $App.LastPassword = $plainPassword
                
                $InfoContent = "--- ORTAK HAVUZ BAĞLANTI BİLGİLERİ ---`r`nAna Bilgisayar Adı: $env:COMPUTERNAME`r`nKullanıcı Adı: $OrtakUser`r`nŞifre: $plainPassword"
                Set-Content -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) "Ortak_Klasor_Baglanti_Bilgileri.txt") -Value $InfoContent -Encoding UTF8
                Write-AppLog "Bağlantı bilgileri masaüstüne txt olarak otomatik kaydedildi." "SUCCESS"
            }

            Show-OperationSummary

            if ($accountCreated) {
                [System.Windows.Forms.MessageBox]::Show("✅ Bu bilgiler masaüstünüze 'Ortak_Klasor_Baglanti_Bilgileri.txt' olarak otomatik kaydedilmiştir.", "Bilgi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        }
    }
}

function Start-ClientConnect {
    Invoke-Safe {
        $hostName = $App.Controls.TxtHost.Text.Trim(); $passwordText = $App.Controls.TxtPass.Text
        if (-not $hostName -or -not $passwordText) { Write-AppLog "Bilgisayar adı ve şifre boş olamaz!" "ERROR"; return }

        Invoke-WithProgress "$hostName hedefine erişim kontrol ediliyor..." {
            if (-not (Test-Connection -ComputerName $hostName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                Write-AppLog "$hostName ağda bulunamadı!" "ERROR"; return
            }
            Set-AppProgress 30

            $remotePath = "\$hostName\OrtakHavuz"
            Start-Process -FilePath "cmdkey.exe" -ArgumentList @("/add:$hostName", "/user:$hostName\OrtakErisim", "/pass:$passwordText") -NoNewWindow -Wait
            Set-AppProgress 60

            Start-Sleep -Seconds 1
            New-DesktopShortcut -ShortcutName "OrtakHavuz_Baglantisi" -TargetPath $remotePath
            Set-AppProgress 90

            Start-Process explorer.exe $remotePath
            Set-AppProgress 100
            Write-AppLog "BAŞARILI! Şifre kaydedildi ve kısayol oluşturuldu." "SUCCESS"
            Show-OperationSummary
        }
    }
}

function Start-RemoveScan {
    Invoke-Safe {
        if ([System.Windows.Forms.MessageBox]::Show("Tarama klasörü ($($Config.Paths.ScanFolder)) ve paylaşımlar SİLİNECEKTİR. Onaylıyor musunuz?", "Onay", "YesNo", "Warning") -eq 'Yes') {
            Invoke-WithProgress "Tarama klasörü temizleniyor..." {
                Remove-SmbShare -Name "Tarama$" -Force -ErrorAction SilentlyContinue; Set-AppProgress 30
                Remove-DesktopItems; Set-AppProgress 60
                if (Test-Path $Config.Paths.ScanFolder) { Remove-Item $Config.Paths.ScanFolder -Recurse -Force -ErrorAction SilentlyContinue }; Set-AppProgress 90
                
                $App.Controls.BtnScan.Text = "Tarama Klasörünü Kur ($($Config.Paths.ScanFolder))"
                $App.Controls.BtnScan.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
                if (-not (Test-Path $Config.Paths.ShareFolder)) { Restore-PowerSettings; Restore-SharingFirewallGroups }
                Set-AppProgress 100
                Write-AppLog "Tarama klasörü kaldırıldı." "SUCCESS"
                Show-OperationSummary
            }
        }
    }
}

function Start-RemoveHost {
    Invoke-Safe {
        if ([System.Windows.Forms.MessageBox]::Show("Ortak Havuz ($($Config.Paths.ShareFolder)), OrtakErisim hesabı ve veriler SİLİNECEKTİR. Onaylıyor musunuz?", "Onay", "YesNo", "Warning") -eq 'Yes') {
            Invoke-WithProgress "Ortak Havuz temizleniyor..." {
                Remove-OrtakErisimCredentials; Set-AppProgress 25
                Remove-SmbShare -Name "OrtakHavuz" -Force -ErrorAction SilentlyContinue
                if (Get-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue) { Remove-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue }
                Set-AppProgress 50
                Remove-DesktopItems; Set-AppProgress 75
                if (Test-Path $Config.Paths.ShareFolder) { Remove-Item $Config.Paths.ShareFolder -Recurse -Force -ErrorAction SilentlyContinue }
                
                $App.Controls.BtnHost.Text = "Ortak Havuz Altyapısını Kur ($($Config.Paths.ShareFolder))"
                $App.Controls.BtnHost.BackColor = [System.Drawing.Color]::Honeydew
                if (-not (Test-Path $Config.Paths.ScanFolder)) { Restore-PowerSettings; Restore-SharingFirewallGroups }
                Set-AppProgress 100
                Write-AppLog "Ortak Havuz kaldırıldı." "SUCCESS"
                Show-OperationSummary
            }
        }
    }
}

function Start-RemoveAll {
    Invoke-Safe {
        if ([System.Windows.Forms.MessageBox]::Show("TÜM yapılandırmalar (Tarama ve OrtakHavuz) kalıcı olarak SİLİNECEKTİR. Emin misiniz?", "Tam Temizlik", "YesNo", "Warning") -eq 'Yes') {
            Invoke-WithProgress "Sistem tamamen temizleniyor..." {
                Remove-OrtakErisimCredentials; Set-AppProgress 20
                Remove-SmbShare -Name "OrtakHavuz" -Force -ErrorAction SilentlyContinue
                Remove-SmbShare -Name "Tarama$" -Force -ErrorAction SilentlyContinue
                if (Get-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue) { Remove-LocalUser -Name "OrtakErisim" -ErrorAction SilentlyContinue }
                Set-AppProgress 40
                Remove-DesktopItems; Set-AppProgress 60
                
                if (Test-Path $Config.Paths.ShareFolder) { Remove-Item $Config.Paths.ShareFolder -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path $Config.Paths.ScanFolder) { Remove-Item $Config.Paths.ScanFolder -Recurse -Force -ErrorAction SilentlyContinue }
                Set-AppProgress 80

                Restore-PowerSettings
                Restore-SharingFirewallGroups

                $App.Controls.BtnScan.Text = "Tarama Klasörünü Kur ($($Config.Paths.ScanFolder))"; $App.Controls.BtnScan.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
                $App.Controls.BtnHost.Text = "Ortak Havuz Altyapısını Kur ($($Config.Paths.ShareFolder))"; $App.Controls.BtnHost.BackColor = [System.Drawing.Color]::Honeydew
                Set-AppProgress 100
                Write-AppLog "Tüm bileşenler başarıyla kaldırıldı." "SUCCESS"
                Show-OperationSummary
            }
        }
    }
}

# =========================================================
# EVENT BINDING
# =========================================================
$App.Controls.BtnScan.Add_Click({ Start-ScanSetup })
$App.Controls.BtnSmb1.Add_Click({ Start-Smb1Enable })
$App.Controls.BtnSmb1Disable.Add_Click({ Start-Smb1Disable })

$App.Controls.BtnCopyPC.Add_Click({ Set-Clipboard $env:COMPUTERNAME; Write-AppLog "Bilgisayar adı panoya kopyalandı." "SUCCESS" })
$App.Controls.BtnCopyPass.Add_Click({ 
    if ($App.LastPassword) { Set-Clipboard $App.LastPassword; Write-AppLog "Şifre panoya kopyalandı." "SUCCESS" } 
    else { Write-AppLog "Bellekte aktif yeni şifre yok (Sadece bu oturumda üretilenler kopyalanabilir)." "WARNING" }
})
$App.Controls.BtnHost.Add_Click({ Start-HostSetup })

$App.Controls.BtnClient.Add_Click({ Start-ClientConnect })

$App.Controls.BtnRemoveTarama.Add_Click({ Start-RemoveScan })
$App.Controls.BtnRemoveOrtak.Add_Click({ Start-RemoveHost })
$App.Controls.BtnRemoveAll.Add_Click({ Start-RemoveAll })

# =========================================================
# BAŞLANGIÇ VE KAPANIŞ (Form Eventleri)
# =========================================================

function Check-SystemStatus {
    Write-AppLog "Sistem başlangıç kontrolü yapılıyor..." "INFO"
    if (Test-Path $Config.Paths.ScanFolder) { $App.Controls.BtnScan.Text = "Tarama Klasörü Zaten Kurulu ($($Config.Paths.ScanFolder))"; $App.Controls.BtnScan.BackColor = [System.Drawing.Color]::WhiteSmoke }
    if (Test-Path $Config.Paths.ShareFolder) { $App.Controls.BtnHost.Text = "Ortak Havuz Zaten Kurulu ($($Config.Paths.ShareFolder))"; $App.Controls.BtnHost.BackColor = [System.Drawing.Color]::WhiteSmoke }
}

$App.Form.Add_Load({
    Load-Settings
    Write-AppLog "PowerShell sürümü: $($PSVersionTable.PSVersion)" "INFO"
    Write-AppLog "Kullanıcı bilgisi: $(whoami)" "INFO"
    Check-SystemStatus
    Write-AppLog "Sistem hazır. (v$ScriptVersion)" "SUCCESS"
})

$App.Form.Add_FormClosing({
    Save-Settings
})

[void]$App.Form.ShowDialog()
