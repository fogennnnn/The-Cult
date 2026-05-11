[CmdletBinding()]
param(
  [string]$ClientPath = "",
  [string]$InstallRoot = "C:\Games\wow",
  [string]$RealmHost = "204.168.209.177",
  [string]$RealmName = "The Cult",
  [string]$AccountName = "",
  [string]$ManifestUrl = "https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/manifest.json",
  [string]$PatchBaseUrl = "https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current",
  [switch]$NoLaunch,
  [switch]$ClearWdbAlways,
  [switch]$SetupLogin,
  [switch]$ForgetLogin,
  [switch]$NoAutoLogin,
  [switch]$NoWindowsHello,
  [switch]$RequireWindowsHello,
  [switch]$InstallShortcut,
  [switch]$TypeAccountOnLogin,
  [switch]$NoLoginSetup,
  [int]$LoginDelaySeconds = 5
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-StateDir {
  $path = Join-Path $env:LOCALAPPDATA "TheCult"
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Get-LoginStorePath {
  return (Join-Path (Get-StateDir) "wow-login.json")
}

function Protect-TextForCurrentUser([string]$Text) {
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $protected = [Security.Cryptography.ProtectedData]::Protect(
    $bytes,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  return [Convert]::ToBase64String($protected)
}

function Unprotect-TextForCurrentUser([string]$ProtectedText) {
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $bytes = [Convert]::FromBase64String($ProtectedText)
  $plain = [Security.Cryptography.ProtectedData]::Unprotect(
    $bytes,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  return [Text.Encoding]::UTF8.GetString($plain)
}

function Get-BootId {
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    return ([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)).ToString("o")
  } catch {
    $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
    return ([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)).ToString("o")
  }
}

function Await-WinRtOperation($Operation, [Type]$ResultType) {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq "AsTask" -and
      $_.IsGenericMethodDefinition -and
      $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -like "IAsyncOperation*"
    } |
    Select-Object -First 1
  if (-not $method) { throw "Windows Runtime async bridge was unavailable." }
  $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  $task.Wait()
  return $task.Result
}

function Invoke-WindowsHelloOncePerBoot {
  if ($NoWindowsHello) { return }

  $bootId = Get-BootId
  $gatePath = Join-Path (Get-StateDir) "windows-hello-boot.txt"
  if ((Test-Path -LiteralPath $gatePath) -and ((Get-Content -LiteralPath $gatePath -Raw).Trim() -eq $bootId)) {
    return
  }

  try {
    [Windows.Security.Credentials.UI.UserConsentVerifier,Windows.Security.Credentials.UI,ContentType=WindowsRuntime] | Out-Null
    $availability = Await-WinRtOperation `
      ([Windows.Security.Credentials.UI.UserConsentVerifier]::CheckAvailabilityAsync()) `
      ([Windows.Security.Credentials.UI.UserConsentVerifierAvailability])

    if ([string]$availability -ne "Available") {
      if ($RequireWindowsHello) { throw "Windows Hello is not available: $availability" }
      Write-Warning "Windows Hello is not available on this PC: $availability. Continuing without Hello."
      return
    }

    $result = Await-WinRtOperation `
      ([Windows.Security.Credentials.UI.UserConsentVerifier]::RequestVerificationAsync("Unlock The Cult auto-login")) `
      ([Windows.Security.Credentials.UI.UserConsentVerificationResult])

    if ([string]$result -ne "Verified") {
      throw "Windows Hello verification failed: $result"
    }

    Set-Content -LiteralPath $gatePath -Encoding ASCII -Value $bootId
  } catch {
    if ($RequireWindowsHello) { throw }
    Write-Warning "Windows Hello gate could not run: $($_.Exception.Message). Continuing without Hello."
  }
}

function Save-LoginSecret([string]$Name) {
  if (-not $Name.Trim()) {
    $Name = Read-Host "WoW account name"
  }
  if (-not $Name.Trim()) { throw "Account name is required." }

  $securePassword = Read-Host "WoW password for $Name" -AsSecureString
  $plainPassword = Get-PlainTextFromSecureString $securePassword
  $encrypted = Protect-TextForCurrentUser $plainPassword
  $plainPassword = $null
  $payload = [ordered]@{
    accountName = $Name.Trim()
    passwordDpapi = $encrypted
    storage = "windows-dpapi-current-user"
    savedAt = (Get-Date).ToString("o")
  }
  $path = Get-LoginStorePath
  Set-Content -LiteralPath $path -Encoding UTF8 -Value ($payload | ConvertTo-Json)
  Write-Step "Saved login for $($payload.accountName) with Windows user encryption."
}

function Remove-LoginSecret {
  $path = Get-LoginStorePath
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
    Write-Step "Forgot saved WoW login."
  }
}

function Get-PlainTextFromSecureString([Security.SecureString]$Secure) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
  }
}

function Load-LoginSecret {
  $path = Get-LoginStorePath
  if (-not (Test-Path -LiteralPath $path)) { return $null }

  try {
    $payload = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $payload.accountName) { return $null }
    $dpapiProperty = $payload.PSObject.Properties["passwordDpapi"]
    if ($dpapiProperty -and $dpapiProperty.Value) {
      return [pscustomobject]@{
        AccountName = [string]$payload.accountName
        Password = Unprotect-TextForCurrentUser ([string]$dpapiProperty.Value)
      }
    }

    Write-Warning "Saved login was created by an older launcher. It will be replaced on the next interactive launch."
    return $null
  } catch {
    Write-Warning "Saved login could not be loaded: $($_.Exception.Message)"
    return $null
  }
}

function Resolve-ClientPath([string]$Path) {
  if (-not $Path) { return $null }
  $candidate = [Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
  if (-not (Test-Path -LiteralPath $candidate)) { return $null }

  if (Test-Path -LiteralPath (Join-Path $candidate "WoW.exe")) { return (Resolve-Path -LiteralPath $candidate).Path }
  if (Test-Path -LiteralPath (Join-Path $candidate "Wow.exe")) { return (Resolve-Path -LiteralPath $candidate).Path }

  $parent = Split-Path -Parent $candidate
  if ($parent -and (Split-Path -Leaf $candidate) -ieq "Data") {
    if (Test-Path -LiteralPath (Join-Path $parent "WoW.exe")) { return (Resolve-Path -LiteralPath $parent).Path }
    if (Test-Path -LiteralPath (Join-Path $parent "Wow.exe")) { return (Resolve-Path -LiteralPath $parent).Path }
  }

  return $null
}

function Find-WowClient {
  $direct = Resolve-ClientPath $ClientPath
  if ($direct) { return $direct }

  $candidates = @(
    $InstallRoot,
    (Get-Location).Path,
    $PSScriptRoot,
    (Join-Path $PSScriptRoot ".."),
    "C:\Games\wow\World of Warcraft Vanilla",
    "C:\Games\World of Warcraft Vanilla",
    "C:\Games\World of Warcraft",
    "$env:USERPROFILE\Games\World of Warcraft Vanilla",
    "$env:USERPROFILE\Desktop\World of Warcraft",
    "$env:USERPROFILE\Downloads\World of Warcraft"
  )

  foreach ($candidate in $candidates) {
    $hit = Resolve-ClientPath $candidate
    if ($hit) { return $hit }
  }

  foreach ($root in @($InstallRoot, "$env:USERPROFILE\Games", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads")) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $wow = Get-ChildItem -LiteralPath $root -Filter "WoW.exe" -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName |
      Select-Object -First 1
    if ($wow) { return $wow.Directory.FullName }
  }

  throw "Could not find WoW.exe. Run with -ClientPath `"C:\path\to\WoW`" once."
}

function Download-File([string]$Url, [string]$Destination, [int]$Retries = 5) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      $ProgressPreference = "SilentlyContinue"
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
      if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
        return
      }
    } catch {
      if ($i -eq $Retries) { throw }
      Start-Sleep -Seconds 1
    }
  }
  throw "Failed to download $Url"
}

function Get-Sha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $bytes = $sha.ComputeHash($stream)
      return ([BitConverter]::ToString($bytes) -replace "-", "").ToLowerInvariant()
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Clear-ClientCache([string]$Root) {
  $paths = @(
    (Join-Path $Root "WDB"),
    (Join-Path $Root "Cache\WDB"),
    (Join-Path $Root "Data\Cache\WDB")
  )
  foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @("itemcache.wdb", "itemnamecache.wdb", "itemtextcache.wdb", "wowcache.wdb") } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}

function Set-ConfigValue([System.Collections.Generic.List[string]]$Lines, [string]$Key, [string]$Value) {
  $seen = $false
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match ('^SET\s+' + [Regex]::Escape($Key) + '\s+')) {
      $Lines[$i] = 'SET ' + $Key + ' "' + $Value.Replace('"', '') + '"'
      $seen = $true
    }
  }
  if (-not $seen) {
    $Lines.Add('SET ' + $Key + ' "' + $Value.Replace('"', '') + '"')
  }
}

function Repair-ClientConfig([string]$Root, [string]$LoginAccountName = "") {
  $realmlist = Join-Path $Root "realmlist.wtf"
  Set-Content -LiteralPath $realmlist -Encoding ASCII -Value @(
    "set realmlist $RealmHost",
    'set patchlist ""'
  )

  $wtf = Join-Path $Root "WTF"
  $config = Join-Path $wtf "Config.wtf"
  New-Item -ItemType Directory -Force -Path $wtf | Out-Null

  $lines = New-Object System.Collections.Generic.List[string]
  if (Test-Path -LiteralPath $config) {
    foreach ($line in (Get-Content -LiteralPath $config)) {
      $lines.Add($line)
    }
  }

  Set-ConfigValue -Lines $lines -Key "realmList" -Value $RealmHost
  Set-ConfigValue -Lines $lines -Key "patchList" -Value ""
  Set-ConfigValue -Lines $lines -Key "realmName" -Value $RealmName
  if ($LoginAccountName.Trim()) {
    Set-ConfigValue -Lines $lines -Key "accountName" -Value $LoginAccountName.Trim()
  }

  Set-Content -LiteralPath $config -Encoding ASCII -Value $lines
}

function Install-Addons([string]$Root, $Manifest) {
  if (-not $Manifest.player_addons) { return }
  foreach ($addon in $Manifest.player_addons) {
    $addonDir = Join-Path (Join-Path $Root "Interface\AddOns") $addon.name
    New-Item -ItemType Directory -Force -Path $addonDir | Out-Null
    foreach ($file in $addon.files) {
      $leaf = Split-Path -Leaf $file
      $url = ($PatchBaseUrl.TrimEnd("/") + "/" + $file.Replace("\", "/"))
      Download-File -Url $url -Destination (Join-Path $addonDir $leaf)
    }
  }
}

function Escape-SendKeysText([string]$Text) {
  if ($null -eq $Text) { return "" }
  $out = New-Object System.Text.StringBuilder
  foreach ($ch in $Text.ToCharArray()) {
    switch ($ch) {
      '+' { [void]$out.Append("{+}") }
      '^' { [void]$out.Append("{^}") }
      '%' { [void]$out.Append("{%}") }
      '~' { [void]$out.Append("{~}") }
      '(' { [void]$out.Append("{(}") }
      ')' { [void]$out.Append("{)}") }
      '[' { [void]$out.Append("{[}") }
      ']' { [void]$out.Append("{]}") }
      '{' { [void]$out.Append("{{}") }
      '}' { [void]$out.Append("{}}") }
      default { [void]$out.Append($ch) }
    }
  }
  return $out.ToString()
}

function Wait-ForWowWindow([int]$TimeoutSeconds = 40) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $proc = Get-Process -Name "WoW" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Select-Object -First 1
    if ($proc) { return $proc }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Invoke-WowAutoLogin([object]$Login) {
  if (-not $Login -or -not $Login.AccountName -or -not $Login.Password) { return }

  Invoke-WindowsHelloOncePerBoot
  Write-Step "Auto-login armed for $($Login.AccountName)."

  $proc = Wait-ForWowWindow
  if (-not $proc) {
    Write-Warning "Could not find WoW window for auto-login."
    return
  }

  Start-Sleep -Seconds ([Math]::Max(1, $LoginDelaySeconds))
  $shell = New-Object -ComObject WScript.Shell
  [void]$shell.AppActivate($proc.Id)
  Start-Sleep -Milliseconds 400

  $password = Escape-SendKeysText $Login.Password

  if ($TypeAccountOnLogin) {
    $account = Escape-SendKeysText $Login.AccountName
    $shell.SendKeys("^a")
    Start-Sleep -Milliseconds 100
    $shell.SendKeys($account)
    Start-Sleep -Milliseconds 100
    $shell.SendKeys("{TAB}")
    Start-Sleep -Milliseconds 100
    $shell.SendKeys("^a")
    Start-Sleep -Milliseconds 100
  }

  $shell.SendKeys($password)
  Start-Sleep -Milliseconds 100
  $shell.SendKeys("{ENTER}")
}

function Install-PlayShortcut([string]$Root) {
  $state = Get-StateDir
  $bootstrap = Join-Path $state "Play-TheCult.bat"
  $repoBootstrap = Join-Path $PSScriptRoot "Play-TheCult.bat"
  if (Test-Path -LiteralPath $repoBootstrap) {
    $sourcePath = (Resolve-Path -LiteralPath $repoBootstrap).Path
    $targetPath = [System.IO.Path]::GetFullPath($bootstrap)
    if ($sourcePath -ine $targetPath) {
      Copy-Item -LiteralPath $repoBootstrap -Destination $bootstrap -Force
    }
  } else {
    Set-Content -LiteralPath $bootstrap -Encoding ASCII -Value @'
@echo off
setlocal EnableExtensions
set "LAUNCHER_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/Play-TheCult.ps1"
set "LAUNCHER_API=https://api.github.com/repos/fogennnnn/The-Cult/contents/patches/current/Play-TheCult.ps1?ref=master"
set "LAUNCHER_DIR=%LOCALAPPDATA%\TheCult"
set "LAUNCHER=%LAUNCHER_DIR%\Play-TheCult.ps1"
set "LAUNCHER_FETCH=%LAUNCHER_URL%?v=%RANDOM%%RANDOM%"
if not exist "%LAUNCHER_DIR%" mkdir "%LAUNCHER_DIR%" >NUL 2>NUL
if exist "%LAUNCHER%" del /F /Q "%LAUNCHER%" >NUL 2>NUL
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $headers=@{'User-Agent'='TheCultLauncher'}; $res=Invoke-WebRequest -Uri $env:LAUNCHER_API -Headers $headers -UseBasicParsing; $json=$res.Content | ConvertFrom-Json; $bytes=[Convert]::FromBase64String(($json.content -replace '\s','')); [IO.File]::WriteAllBytes($env:LAUNCHER,$bytes); exit 0 } catch { try { Invoke-WebRequest -Uri $env:LAUNCHER_FETCH -OutFile $env:LAUNCHER -UseBasicParsing; exit 0 } catch { Write-Host $_; exit 1 } }"
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
exit /b %ERRORLEVEL%
'@
  }

  $desktop = [Environment]::GetFolderPath("Desktop")
  $shortcutPath = Join-Path $desktop "The Cult.lnk"
  $wow = Join-Path $Root "WoW.exe"
  if (-not (Test-Path -LiteralPath $wow)) { $wow = Join-Path $Root "Wow.exe" }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $bootstrap
  $shortcut.WorkingDirectory = $Root
  $shortcut.IconLocation = "$wow,0"
  $shortcut.Description = "The Cult auto-updating WoW launcher"
  $shortcut.Save()
  Write-Step "Installed desktop shortcut: $shortcutPath"
}

function Ensure-CurrentPatch([string]$Root) {
  Write-Step "Checking client patch manifest."
  $work = Join-Path $env:TEMP "the-cult-launcher"
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  $manifestPath = Join-Path $work "manifest.json"
  Download-File -Url $ManifestUrl -Destination $manifestPath
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

  $patchName = $manifest.patch.file
  $expectedHash = ([string]$manifest.patch.sha256).ToLowerInvariant()
  $expectedBytes = [int64]$manifest.patch.bytes
  $data = Join-Path $Root "Data"
  $destination = Join-Path $data $patchName
  $currentHash = Get-Sha256 $destination
  $patchChanged = $currentHash -ne $expectedHash

  if ($patchChanged) {
    if (Get-Process -Name "WoW" -ErrorAction SilentlyContinue) {
      throw "WoW.exe is running. Close it before patching."
    }

    Write-Step "New client patch found. Downloading $patchName."
    $download = Join-Path $work $patchName
    Download-File -Url ($PatchBaseUrl.TrimEnd("/") + "/" + $patchName) -Destination $download

    $downloadHash = Get-Sha256 $download
    if ($downloadHash -ne $expectedHash) {
      throw "Downloaded patch hash mismatch. Expected $expectedHash, got $downloadHash."
    }
    $downloadBytes = (Get-Item -LiteralPath $download).Length
    if ($downloadBytes -ne $expectedBytes) {
      throw "Downloaded patch size mismatch. Expected $expectedBytes, got $downloadBytes."
    }

    if (Test-Path -LiteralPath $destination) {
      $backup = Join-Path $data ($patchName + ".before-" + (Get-Date -Format "yyyyMMddHHmmss") + ".MPQ")
      Copy-Item -LiteralPath $destination -Destination $backup -Force
    }

    Copy-Item -LiteralPath $download -Destination $destination -Force
    Set-Content -LiteralPath (Join-Path $data ($patchName + ".cult-version.json")) -Encoding UTF8 -Value ($manifest | ConvertTo-Json -Depth 8)
    Clear-ClientCache -Root $Root
    Write-Step "Patch updated and cache cleared."
  } else {
    Write-Step "Client patch is current."
    if ($ClearWdbAlways) { Clear-ClientCache -Root $Root }
  }

  Install-Addons -Root $Root -Manifest $manifest
}

$client = Find-WowClient
Write-Step "Using client at $client"

if ($ForgetLogin) {
  Remove-LoginSecret
}

if ($SetupLogin) {
  Save-LoginSecret -Name $AccountName
}

$login = $null
if (-not $NoAutoLogin) {
  $login = Load-LoginSecret
  if (-not $login -and -not $NoLaunch -and -not $NoLoginSetup) {
    Write-Step "No saved login found. Saving one now so future launches go straight in."
    Save-LoginSecret -Name $AccountName
    $login = Load-LoginSecret
  }
}

$effectiveAccountName = $AccountName
if (-not $effectiveAccountName -and $login -and $login.AccountName) {
  $effectiveAccountName = $login.AccountName
}

Repair-ClientConfig -Root $client -LoginAccountName $effectiveAccountName
Ensure-CurrentPatch -Root $client

if ($InstallShortcut) {
  Install-PlayShortcut -Root $client
}

$wow = Join-Path $client "WoW.exe"
if (-not (Test-Path -LiteralPath $wow)) { $wow = Join-Path $client "Wow.exe" }
if ($NoLaunch) {
  Write-Step "Ready. Launch skipped because -NoLaunch was set."
  return
}

Write-Step "Launching The Cult."
$process = Start-Process -FilePath $wow -WorkingDirectory $client -PassThru
if ($login) {
  Invoke-WowAutoLogin -Login $login
}
