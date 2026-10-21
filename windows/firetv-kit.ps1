# Fire TV Clean-Up Kit (Windows)
# Launched by START-HERE.bat. Every change it makes can be undone from the menu (option 8).
# Works only on Fire TVs running Fire OS, which is Android-based. Vega OS devices can't be modified.
# Keep this file plain ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$KitRoot    = Split-Path -Parent $PSScriptRoot
$ToolsDir   = Join-Path $KitRoot 'tools'
$MyTvDir    = Join-Path $KitRoot 'my-tv'
$DisableTxt = Join-Path (Join-Path $KitRoot 'config') 'disable.txt'
$IpFile     = Join-Path $MyTvDir 'tv-ip.txt'
$OnWindows  = ($env:OS -eq 'Windows_NT')

$ProjectivyPkg   = 'com.spocky.projengmenu'
$ProjectivyA11y  = "$ProjectivyPkg/.services.ProjectivyAccessibilityService"
$ProjectivyNotif = "$ProjectivyPkg/.services.notification.NotificationListener"
$DnsHost         = 'dns.adguard-dns.com'

$script:Adb    = $null
$script:Serial = $null

# ---------- small helpers ----------

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }
function Title([string]$Text) { Write-Host ''; Write-Host "=== $Text ===" -ForegroundColor Cyan; Write-Host '' }
function Wait-Enter([string]$Prompt = 'Press Enter to go back to the menu') { [void](Read-Host "`n$Prompt") }

function Ask-YesNo([string]$Question) {
    while ($true) {
        $a = "$(Read-Host "$Question (y/n)")".Trim().ToLower()
        if ($a -eq 'y' -or $a -eq 'yes') { return $true }
        if ($a -eq 'n' -or $a -eq 'no')  { return $false }
    }
}

# Runs adb against the TV and returns its output as plain text lines.
function Invoke-Adb {
    $out = & $script:Adb -s $script:Serial @args 2>&1
    return @($out | ForEach-Object { "$_".TrimEnd("`r") })
}
function TvShell([string]$Command) { return @(Invoke-Adb shell $Command) }
function TvValue([string]$Command) { return ((TvShell $Command) -join '').Trim() }

# ---------- adb setup and connection ----------

function Initialize-Adb {
    if ($script:Adb) { return $true }
    if ($OnWindows) {
        $exe = Join-Path (Join-Path $ToolsDir 'platform-tools') 'adb.exe'
        if (-not (Test-Path $exe)) {
            Say "First time only: downloading Google's official Android tools (about 15 MB)..." Yellow
            New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
            $zip = Join-Path $ToolsDir 'platform-tools.zip'
            try {
                Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
                Expand-Archive -Path $zip -DestinationPath $ToolsDir -Force
                Remove-Item $zip -ErrorAction SilentlyContinue
            } catch {
                Say "Download failed: $($_.Exception.Message)" Red
                Say 'Make sure this computer is online, then close this window and double-click START-HERE.bat again.' Red
                return $false
            }
        }
        $script:Adb = $exe
    } else {
        # Lets the kit be tested from a Mac with PowerShell installed.
        $cmd = Get-Command adb -ErrorAction SilentlyContinue
        if (-not $cmd) { Say 'adb not found. On a Mac run: brew install --cask android-platform-tools' Red; return $false }
        $script:Adb = $cmd.Source
    }
    & $script:Adb start-server 2>&1 | Out-Null
    return $true
}

# Quick check (2.5 s max) that the TV answers on the ADB port, so adb never hangs on a sleeping TV.
function Test-TvPort([string]$Ip) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $wait = $client.BeginConnect($Ip, 5555, $null, $null)
        return ($wait.AsyncWaitHandle.WaitOne(2500) -and $client.Connected)
    } catch { return $false } finally { $client.Close() }
}
function Get-SerialIp { return ($script:Serial -replace ':5555$', '') }

function Get-TvState {
    if (-not $script:Serial) { return 'none' }
    $s = "$(& $script:Adb -s $script:Serial get-state 2>&1)".Trim()
    if ($s -eq 'device') { return 'device' }
    if ($s -match 'unauthorized') { return 'unauthorized' }
    return 'offline'
}

function Connect-Tv {
    Title 'Connect to your TV'
    if (-not (Initialize-Adb)) { return $false }
    $saved = ''
    if (Test-Path $IpFile) { $saved = "$(Get-Content $IpFile -Raw)".Trim() }
    Say "Your TV's IP address is on the TV under: Settings > My Fire TV > About > Network"
    if ($saved) {
        $ip = "$(Read-Host "Type the TV's IP address, or just press Enter to use $saved")".Trim()
        if (-not $ip) { $ip = $saved }
    } else {
        $ip = "$(Read-Host "Type the TV's IP address (it looks like 192.168.1.50)")".Trim()
    }
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        Say "'$ip' doesn't look right. It should be 4 numbers with dots between them, like 192.168.1.50" Red
        return $false
    }
    New-Item -ItemType Directory -Force -Path $MyTvDir | Out-Null
    Set-Content -Path $IpFile -Value $ip
    $script:Serial = "${ip}:5555"

    Say "Connecting to $ip ..."
    & $script:Adb disconnect $script:Serial 2>&1 | Out-Null
    if (-not (Test-TvPort $ip)) {
        Say "Can't reach the TV at $ip." Red
        Say 'Check these, then pick option 1 again:' Red
        Say '  1. The TV is turned on (not asleep).' Red
        Say '  2. On the TV, Developer Options > ADB debugging is ON. (After a TV restart, switch it OFF and ON again.)' Red
        Say '  3. The IP address is typed correctly.' Red
        Say '  4. This computer and the TV are on the same Wi-Fi.' Red
        return $false
    }
    $told = $false
    for ($i = 0; $i -lt 60; $i++) {
        $reply = "$(& $script:Adb connect $script:Serial 2>&1)".Trim()
        $state = Get-TvState
        if ($state -eq 'device') { Say 'Connected to your TV!' Green; return $true }
        if ($state -eq 'unauthorized') {
            if (-not $told) {
                Say ''
                Say '>>> LOOK AT YOUR TV NOW <<<' Yellow
                Say 'A box says "Allow USB debugging?"' Yellow
                Say 'With the remote, tick "Always allow from this computer", then press OK.' Yellow
                Say '(Waiting up to 2 minutes...)'
                $told = $true
            }
        } elseif ($i -ge 2 -and $reply -match 'refused|unable|cannot|timed out|No route|failed to connect') {
            Say "Can't reach the TV. ($reply)" Red
            Say 'Check these, then pick option 1 again:' Red
            Say '  1. The TV is turned on.' Red
            Say '  2. On the TV, Developer Options > ADB debugging is ON. (After a TV restart, switch it OFF and ON again.)' Red
            Say '  3. The IP address is typed correctly.' Red
            Say '  4. This computer and the TV are on the same Wi-Fi.' Red
            return $false
        }
        Start-Sleep -Seconds 2
    }
    Say 'Gave up waiting for the OK on the TV. Pick option 1 to try again.' Red
    return $false
}

# Makes sure we're connected before a step runs. Offers to connect if not.
function Assert-Tv {
    if (-not (Initialize-Adb)) { return $false }
    if ($script:Serial -and (Test-TvPort (Get-SerialIp))) {
        & $script:Adb connect $script:Serial 2>&1 | Out-Null
        if ((Get-TvState) -eq 'device') { return $true }
    }
    Say "Not connected to the TV yet, so let's do that first." Yellow
    return (Connect-Tv)
}

# ---------- the steps ----------

function Show-TvCheck {
    Title 'Step 1 - Check your TV and save a backup'
    if (-not (Assert-Tv)) { return $false }
    $os    = TvValue 'getprop ro.build.version.name'
    $model = TvValue 'getprop ro.product.model'
    $sdk   = 0
    [void][int]::TryParse((TvValue 'getprop ro.build.version.sdk'), [ref]$sdk)
    Say "TV model:  $model"
    Say "Software:  $os"
    if ($os -notmatch 'Fire OS') {
        Say ''
        Say 'STOP: this TV is not running Fire OS (it may be Vega OS). This kit cannot change it.' Red
        return $false
    }
    if ($sdk -lt 28) {
        Say 'Heads up: this is an older Fire OS. Most steps should work, but the new home screen may not stick.' Yellow
    }
    New-Item -ItemType Directory -Force -Path $MyTvDir | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $all = @(TvShell 'pm list packages' | ForEach-Object { $_ -replace '^package:', '' } | Sort-Object)
    $off = @(TvShell 'pm list packages -d' | ForEach-Object { $_ -replace '^package:', '' } | Sort-Object)
    Set-Content -Path (Join-Path $MyTvDir "backup-$stamp-all-apps.txt") -Value $all
    Set-Content -Path (Join-Path $MyTvDir "backup-$stamp-already-off.txt") -Value $off
    Say "Apps on the TV: $($all.Count). Saved a backup list in the 'my-tv' folder." Green
    Say "Free memory right now: $(Get-FreeMemoryMb) MB"
    return $true
}

function Get-FreeMemoryMb {
    $line = TvValue 'grep MemAvailable /proc/meminfo'
    if ($line -match '(\d+)') { return [math]::Round([int64]$Matches[1] / 1024) }
    return '?'
}

function Get-DisableList {
    return @(Get-Content $DisableTxt | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
}

function Invoke-Debloat {
    Title 'Step 2 - Turn off Amazon ads, tracking and junk apps'
    if (-not (Assert-Tv)) { return $false }
    $list = Get-DisableList
    Say "This turns off $($list.Count) Amazon apps and services: ads, tracking, shopping,"
    Say 'the ad screensaver, pop-ups, and extras like Amazon Photos, Amazon Music and the Silk browser.'
    Say 'NOT touched: Prime Video, the Appstore, Alexa, Live TV, AirPlay, HDMI inputs.' Green
    Say 'Nothing gets deleted. Option 8 (UNDO) turns it all back on.'
    Say ''
    if (-not (Ask-YesNo 'Go ahead?')) { return $false }
    $installed = @(TvShell 'pm list packages'    | ForEach-Object { $_ -replace '^package:', '' })
    $disabled  = @(TvShell 'pm list packages -d' | ForEach-Object { $_ -replace '^package:', '' })
    $ok = 0; $skip = 0; $fail = 0
    foreach ($p in $list) {
        if ($installed -notcontains $p) { Say "  -   $p (not on this TV)" DarkGray; $skip++; continue }
        if ($disabled -contains $p)     { Say "  =   $p (already off)" DarkGray; $ok++; continue }
        $out = (TvShell "pm disable-user --user 0 $p") -join ' '
        if ($out -match 'new state: disabled') { Say "  OK  $p" Green; $ok++ }
        else { Say "  !!  $p : $out" Red; $fail++ }
    }
    Say ''
    Say "Done: $ok turned off, $skip not on this TV, $fail couldn't be changed." Cyan
    return $true
}

function Install-Projectivy {
    Title 'Step 3 - Install the Projectivy home screen'
    if (-not (Assert-Tv)) { return $false }
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    try {
        $rel   = Invoke-RestMethod -Uri 'https://api.github.com/repos/spocky/miproja1/releases/latest' -Headers @{ 'User-Agent' = 'firetv-kit' }
        $asset = $rel.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
        if (-not $asset) { throw 'the latest release has no APK file' }
        $apk = Join-Path $ToolsDir $asset.name
        if (-not (Test-Path $apk)) {
            Say "Downloading Projectivy $($rel.tag_name) from its developer's GitHub ($([math]::Round($asset.size / 1MB, 1)) MB)..." Yellow
            Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $apk
        }
    } catch {
        Say "Couldn't download Projectivy: $($_.Exception.Message)" Red
        return $false
    }

    Say 'Installing it on the TV (can take a minute)...'
    $out = (Invoke-Adb install -r $apk) -join ' '
    if ($out -notmatch 'Success') { Say "Install failed: $out" Red; return $false }
    Say '  OK  Projectivy installed' Green

    # Permissions that let Projectivy take over the Home button. Keep any accessibility services already on.
    $current = TvValue 'settings get secure enabled_accessibility_services'
    if (-not $current -or $current -eq 'null') { $new = $ProjectivyA11y }
    elseif ($current -notmatch [regex]::Escape($ProjectivyA11y)) { $new = "${current}:$ProjectivyA11y" }
    else { $new = $current }
    TvShell "settings put secure enabled_accessibility_services $new" | Out-Null
    TvShell 'settings put secure accessibility_enabled 1' | Out-Null
    TvShell "cmd notification allow_listener $ProjectivyNotif" | Out-Null
    TvShell "cmd role add-role-holder android.app.role.HOME $ProjectivyPkg" | Out-Null

    if ((TvValue 'settings get secure enabled_accessibility_services') -match 'ProjectivyAccessibilityService') {
        Say '  OK  Home-button permission is on' Green
    } else {
        Say "  !!  Couldn't switch on the Home-button permission. Projectivy will still open, but Home may go to Amazon's screen." Red
    }

    TvShell "am start -n $ProjectivyPkg/.ui.home.MainActivity" | Out-Null
    Say ''
    Say '>>> NOW, ON THE TV <<<' Yellow
    Say '  1. Projectivy has opened. Click through its welcome screens.' Yellow
    Say '  2. Open its Settings > General and turn ON "Override current launcher".' Yellow
    Say '  3. Press Home on the remote. You should land in Projectivy.' Yellow
    return $true
}

function Resolve-OnTv([string]$Name) {
    $first = (TvShell "ping -c 1 -W 2 $Name") | Select-Object -First 1
    if ($first -match '^PING \S+ \(([\d.]+)\)') { return $Matches[1] }
    return 'not found'
}

function Enable-PrivacyDns {
    Title 'Step 4 - Block Amazon tracking servers'
    if (-not (Assert-Tv)) { return $false }
    Say "This points the TV's internet look-ups at AdGuard DNS, a free service that blocks"
    Say "Amazon's tracking and ad servers. Only the TV changes, not your router."
    Say 'If an app ever stops working, option 9 switches this off.'
    Say ''
    if (-not (Ask-YesNo 'Go ahead?')) { return $false }
    TvShell "settings put global private_dns_specifier $DnsHost" | Out-Null
    TvShell 'settings put global private_dns_mode hostname' | Out-Null
    Say 'Testing (a few seconds)...'
    Start-Sleep -Seconds 6

    $good = $true
    foreach ($d in @('device-metrics-us.amazon.com', 'mads.amazon.com', 'aax-us-east.amazon-adsystem.com')) {
        $ip = Resolve-OnTv $d
        if ($ip -eq '0.0.0.0' -or $ip -eq '127.0.0.1') { Say ("  BLOCKED  {0}" -f $d) Green }
        else { Say ("  open     {0} ({1})" -f $d, $ip) Yellow }
    }
    foreach ($d in @('atv-ps.amazon.com', 'www.netflix.com', 'tv.apple.com')) {
        $ip = Resolve-OnTv $d
        if ($ip -eq 'not found' -or $ip -eq '0.0.0.0' -or $ip -eq '127.0.0.1') { Say ("  BROKEN   {0}" -f $d) Red; $good = $false }
        else { Say ("  working  {0}" -f $d) Green }
    }
    if (-not $good) {
        Say ''
        Say "Some normal sites aren't loading. Use option 9 to switch the tracking block off." Red
    }
    return $true
}

function Disable-PrivacyDns {
    Title 'Switch off the tracking block'
    if (-not (Assert-Tv)) { return $false }
    TvShell 'settings put global private_dns_mode opportunistic' | Out-Null
    TvShell 'settings delete global private_dns_specifier' | Out-Null
    Say '  OK  Tracking block is off. The TV uses normal internet look-ups again.' Green
    Say '  (Turn it back on any time with option 6.)'
    return $true
}

function Show-Status {
    Title "What's changed on your TV"
    if (-not (Assert-Tv)) { return $false }
    $list     = Get-DisableList
    $disabled = @(TvShell 'pm list packages -d' | ForEach-Object { $_ -replace '^package:', '' })
    $offCount = @($list | Where-Object { $disabled -contains $_ }).Count
    $hasProj  = (TvValue "pm list packages $ProjectivyPkg") -match $ProjectivyPkg
    $dnsMode  = TvValue 'settings get global private_dns_mode'
    $dnsHost  = TvValue 'settings get global private_dns_specifier'
    Say "Amazon junk turned off:  $offCount of $($list.Count)"
    if ($hasProj) { Say 'Projectivy home screen:  installed' } else { Say 'Projectivy home screen:  not installed' }
    if ($dnsMode -eq 'hostname') { Say "Tracking block (DNS):    ON ($dnsHost)" } else { Say 'Tracking block (DNS):    off' }
    Say "Free memory right now:   $(Get-FreeMemoryMb) MB"
    return $true
}

function Undo-All {
    Title 'UNDO everything'
    if (-not (Assert-Tv)) { return $false }
    Say 'This turns every Amazon app back on and switches off the tracking block.'
    if (-not (Ask-YesNo 'Go ahead?')) { return $false }
    $disabled = @(TvShell 'pm list packages -d' | ForEach-Object { $_ -replace '^package:', '' })
    foreach ($p in Get-DisableList) {
        if ($disabled -notcontains $p) { continue }
        $out = (TvShell "pm enable --user 0 $p") -join ' '
        if ($out -match 'new state: enabled') { Say "  ON  $p" Green } else { Say "  !!  $p : $out" Red }
    }
    TvShell 'settings put global private_dns_mode opportunistic' | Out-Null
    TvShell 'settings delete global private_dns_specifier' | Out-Null
    Say '  OK  Tracking block switched off' Green
    if (Ask-YesNo "Also remove Projectivy? (Amazon's home screen comes back)") {
        $out = (Invoke-Adb uninstall $ProjectivyPkg) -join ' '
        if ($out -match 'Success') { Say '  OK  Projectivy removed' Green } else { Say "  !!  $out" Red }
    }
    Say ''
    Say 'Done. Restart the TV to finish: Settings > My Fire TV > Restart.' Cyan
    return $true
}

function Invoke-Everything {
    if (-not (Show-TvCheck)) { return }
    Wait-Enter 'Press Enter for the next step'
    if (-not (Invoke-Debloat)) { return }
    Wait-Enter 'Press Enter for the next step'
    if (-not (Install-Projectivy)) { return }
    Wait-Enter 'When Projectivy is set up on the TV, press Enter for the last step'
    if (-not (Enable-PrivacyDns)) { return }
    Say ''
    Say 'ALL DONE! Enjoy the faster, ad-free TV.' Green
    Say 'Last check: restart the TV (Settings > My Fire TV > Restart), then press Home.' Green
}

# ---------- menu ----------

if (Test-Path $IpFile) { $script:Serial = "$("$(Get-Content $IpFile -Raw)".Trim()):5555" }
Say 'Getting ready...'
if (-not (Initialize-Adb)) { Wait-Enter 'Press Enter to close'; return }
if ($script:Serial -and (Test-TvPort (Get-SerialIp))) {
    & $script:Adb connect $script:Serial 2>&1 | Out-Null
}

while ($true) {
    Clear-Host
    Say '=============================================' Cyan
    Say '          FIRE TV CLEAN-UP KIT' Cyan
    Say '=============================================' Cyan
    if ((Get-TvState) -eq 'device') { Say "  Connected to TV at $(Get-SerialIp)" Green }
    else { Say '  Not connected to a TV yet (start with 1)' Yellow }
    Say ''
    Say '  1) Connect to my TV'
    Say '  2) DO EVERYTHING (recommended) - runs Steps 1 to 4 in order' White
    Say '  3) Step 1: Check my TV and save a backup'
    Say '  4) Step 2: Turn off Amazon ads, tracking and junk apps'
    Say '  5) Step 3: Install the Projectivy home screen'
    Say '  6) Step 4: Block Amazon tracking servers'
    Say "  7) Show what's changed"
    Say '  8) UNDO everything'
    Say '  9) Switch off just the tracking block (if an app has trouble)'
    Say '  Q) Quit'
    Say ''
    $choice = "$(Read-Host 'Type a number and press Enter')".Trim().ToUpper()
    switch ($choice) {
        '1' { [void](Connect-Tv);          Wait-Enter }
        '2' { Invoke-Everything;           Wait-Enter }
        '3' { [void](Show-TvCheck);        Wait-Enter }
        '4' { [void](Invoke-Debloat);      Wait-Enter }
        '5' { [void](Install-Projectivy);  Wait-Enter }
        '6' { [void](Enable-PrivacyDns);   Wait-Enter }
        '7' { [void](Show-Status);         Wait-Enter }
        '8' { [void](Undo-All);            Wait-Enter }
        '9' { [void](Disable-PrivacyDns);  Wait-Enter }
        'Q' { return }
        default { }
    }
}
