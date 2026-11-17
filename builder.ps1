<#
  SUBSTRATUM drop-in builder (Windows).
  Drop this folder next to apotheosisEngine.exe (or a .love, or an unpacked tree)
  and double-click build.bat, or:
    .\build.ps1 -Target desktop
    .\build.ps1 -Target android
    .\build.ps1 -Target desktop -Update      # force re-fetch loader from GitHub
#>
param(
  [ValidateSet("desktop", "android", "ask")] [string]$Target = "ask",
  [string]$GameDir = "",
  [string]$OutDir = "",
  [string]$AndroidSrc = "",
  [switch]$FetchAndroid,
  [switch]$Update,
  [string]$Repo = "nikere/Substratum",
  [string]$Branch = "",
  [string]$RepoZip = "",
  [string]$AndroidDir = "androidlua",
  [string]$LoveUrl = "https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip",
  [string]$LoveAndroidUrl = "https://github.com/love2d/love/archive/refs/tags/11.5.zip"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RelDir    = $ScriptDir
$CacheDir  = Join-Path $env:LOCALAPPDATA "Substratum"
$MARKER    = "[SUBSTRATUM]"
$sw        = [Diagnostics.Stopwatch]::StartNew()
$Work      = $null

function Step($m) { Write-Host ("[{0,5:N1}s] {1}" -f $sw.Elapsed.TotalSeconds, $m) -ForegroundColor Cyan }

function Resolve-OutDir {
  if ($OutDir) { return $OutDir }
  $probe = Join-Path $ScriptDir ".apot_probe"
  try {
    [IO.File]::WriteAllText($probe, "x"); Remove-Item $probe -Force
    return (Join-Path $ScriptDir "out")
  } catch {
    $d = Join-Path ([Environment]::GetFolderPath("Desktop")) "Substratum-out"
    Write-Host "[i] Folder is write-protected; output goes to $d" -ForegroundColor Yellow
    return $d
  }
}

function Find-ZipStart([string]$Path) {
  $fs = [IO.File]::OpenRead($Path)
  try {
    $len = $fs.Length; $tailN = [int][Math]::Min($len, 65657)
    $fs.Seek(-$tailN, 'End') | Out-Null
    $tail = New-Object byte[] $tailN
    $read = 0; while ($read -lt $tailN) { $r = $fs.Read($tail, $read, $tailN - $read); if ($r -le 0) { break }; $read += $r }
    for ($i = $read - 22; $i -ge 0; $i--) {
      if ($tail[$i] -eq 0x50 -and $tail[$i+1] -eq 0x4B -and $tail[$i+2] -eq 0x05 -and $tail[$i+3] -eq 0x06) {
        $cdSize = [long][BitConverter]::ToUInt32($tail, $i + 12); $cdOff = [long][BitConverter]::ToUInt32($tail, $i + 16)
        if ($cdOff -eq 0xFFFFFFFF -or $cdSize -eq 0xFFFFFFFF) {
          for ($z = $i - 4; $z -ge 0; $z--) {
            if ($tail[$z] -eq 0x50 -and $tail[$z+1] -eq 0x4B -and $tail[$z+2] -eq 0x06 -and $tail[$z+3] -eq 0x06) {
              $cdSize = [long][BitConverter]::ToUInt64($tail, $z + 40); $cdOff = [long][BitConverter]::ToUInt64($tail, $z + 48); break
            }
          }
        }
        return (($len - $tailN + $i) - $cdSize) - $cdOff
      }
    }
    throw "No zip EOCD inside $Path (not a fused exe?)"
  } finally { $fs.Close() }
}

function Apply-UnifiedPatch([string]$PatchFile, [string]$BaseDir) {
  if (-not (Test-Path $PatchFile)) { throw "Missing patch: $PatchFile" }
  $script:pf_cur = $null; $script:pf_lines = $null
  $script:pf_old = New-Object System.Collections.Generic.List[string]
  $script:pf_new = New-Object System.Collections.Generic.List[string]
  $flush = {
    if ($script:pf_old.Count -eq 0 -and $script:pf_new.Count -eq 0) { return }
    if ($script:pf_old.Count -eq 0) { throw "Empty-context hunk in $($script:pf_cur): regenerate $(Split-Path $PatchFile -Leaf) with -U2+" }
    $content = $script:pf_lines -join "`n"; $oldBlock = $script:pf_old -join "`n"; $newBlock = $script:pf_new -join "`n"
    if (-not $content.Contains($oldBlock)) {
      if ($content.Contains($newBlock)) { $script:pf_old.Clear(); $script:pf_new.Clear(); return }
      throw "Context mismatch in $($script:pf_cur) ($(Split-Path $PatchFile -Leaf)) - game version changed?"
    }
    $idx = $content.IndexOf($oldBlock)
    if ($content.IndexOf($oldBlock, $idx + 1) -ge 0) { throw "Ambiguous hunk in $($script:pf_cur)" }
    $content = $content.Substring(0, $idx) + $newBlock + $content.Substring($idx + $oldBlock.Length)
    $script:pf_lines = $content -split "`n"
    $script:pf_old.Clear(); $script:pf_new.Clear()
  }
  $write = { if ($script:pf_cur) {
      [IO.File]::WriteAllText((Join-Path $BaseDir $script:pf_cur), ($script:pf_lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    } }
  foreach ($line in (Get-Content $PatchFile -Encoding UTF8)) {
    if ($line -like "+++ *") {
      & $flush; & $write
      $script:pf_cur = $line.Substring(4).Trim() -replace "^[ab]/", "" -replace "/", "\"
      $tp = Join-Path $BaseDir $script:pf_cur
      if (-not (Test-Path $tp)) { throw "Patch target missing: $($script:pf_cur)" }
      $script:pf_lines = ((Get-Content $tp -Raw -Encoding UTF8) -replace "`r`n", "`n") -split "`n"
    }
    elseif ($line -like "@@*") { & $flush }
    elseif ($line -like "--- *") { }
    elseif ($line -like "\*") { }
    elseif ($script:pf_cur) {
      if ($line -like "+*") { $script:pf_new.Add($line.Substring(1)) }
      elseif ($line -like "-*") { $script:pf_old.Add($line.Substring(1)) }
      elseif ($line -like " *") { $t = $line.Substring(1); $script:pf_old.Add($t); $script:pf_new.Add($t) }
      elseif ($line -eq "") { $script:pf_old.Add(""); $script:pf_new.Add("") }
    }
  }
  & $flush; & $write
  Step "Applied $(Split-Path $PatchFile -Leaf)"
}

function New-NormalizedZip([string]$SourceDir, [string]$DestZip) {
  if (Test-Path $DestZip) { Remove-Item $DestZip -Force }
  $root = (Resolve-Path $SourceDir).Path.TrimEnd('\', '/')
  $za = [IO.Compression.ZipFile]::Open($DestZip, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
      $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally { $za.Dispose() }
}

function Invoke-Download([string]$Url, [string]$OutFile) {
  $tmp = "$OutFile.part"
  if (Test-Path $tmp) { Remove-Item $tmp -Force }
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -fL --retry 3 --connect-timeout 20 --progress-bar $Url -o $tmp
    if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit $LASTEXITCODE): $Url" }
  } else {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Substratum-Builder/1.0")
    $wc.DownloadFile($Url, $tmp)
  }
  $fs = [IO.File]::OpenRead($tmp)
  try {
    if ($fs.Length -lt 1024) { throw "Downloaded file too small: $Url" }
    $hdr = New-Object byte[] 2; [void]$fs.Read($hdr, 0, 2)
    if ($hdr[0] -ne 0x50 -or $hdr[1] -ne 0x4B) { throw "Not a ZIP (got a web page?): $Url" }
  } finally { $fs.Close() }
  Move-Item -LiteralPath $tmp -Destination $OutFile -Force
}

function Get-Release {
  $haveLocal = (Test-Path (Join-Path $RelDir "mods\init.lua")) -and (Test-Path (Join-Path $RelDir "patches\main.lua.patch"))
  if ($haveLocal -and -not $Update) { Step "Using local loader files."; return $RelDir }
  Step "Fetching loader + patches from GitHub ($Repo)..."
  $zip = Join-Path $Work "repo.zip"
  $ext = Join-Path $Work "repo"
  $urls = @()
  if ($RepoZip) { $urls += $RepoZip }
  if ($Branch) { $urls += "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" }
  else { $urls += "https://codeload.github.com/$Repo/zip/refs/heads/main"
         $urls += "https://codeload.github.com/$Repo/zip/refs/heads/master" }
  $ok = $false
  foreach ($u in $urls) { try { Invoke-Download $u $zip; $ok = $true; break } catch { Write-Host "  ...$u failed, trying next" -ForegroundColor DarkGray } }
  if (-not $ok) { throw "Could not download the loader repo. Check the name/branch, or run offline with mods/ + patches/ present." }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $ext)
  $inner = Get-ChildItem $ext -Directory | Where-Object { Test-Path (Join-Path $_.FullName "mods\init.lua") } | Select-Object -First 1
  if (-not $inner) { $inner = Get-ChildItem $ext -Directory | Select-Object -First 1 }
  if (-not $inner) { throw "Repo archive contained no folders." }
  Step "Loader fetched: $($inner.Name)"
  return $inner.FullName
}

function Get-LoveRuntime {
  New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
  $zip = Join-Path $CacheDir "love-11.5-win64.zip"
  $rt  = Join-Path $CacheDir "runtime-win64"
  $exe = if (Test-Path $rt) { Get-ChildItem $rt -Recurse -Filter love.exe -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
  if (-not $exe) {
    if (Test-Path $zip) { try { $t = [IO.Compression.ZipFile]::OpenRead($zip); $t.Dispose() } catch { Remove-Item $zip -Force } }
    if (-not (Test-Path $zip)) { Step "Downloading LOVE 11.5 win64 runtime..."; Invoke-Download $LoveUrl $zip }
    Step "Extracting runtime (cached in %LOCALAPPDATA%\Substratum)..."
    if (Test-Path $rt) { Remove-Item $rt -Recurse -Force }
    New-Item -ItemType Directory -Path $rt -Force | Out-Null
    try { [IO.Compression.ZipFile]::ExtractToDirectory($zip, $rt) }
    catch { Remove-Item $zip -Force -ErrorAction SilentlyContinue; throw }
    $exe = Get-ChildItem $rt -Recurse -Filter love.exe | Select-Object -First 1
    if (-not $exe) { throw "love.exe not found inside the runtime archive." }
  }
  return $exe.DirectoryName
}

# .NET Framework cannot open a zip with prepended data: slice fused exes first.
function Test-LoveZip([string]$Path, [string[]]$Need, [string]$Marker) {
  $probe = $Path
  $fs0 = [IO.File]::OpenRead($Path); $hdr = New-Object byte[] 2; [void]$fs0.Read($hdr, 0, 2); $fs0.Close()
  if ($hdr[0] -eq 0x4D -and $hdr[1] -eq 0x5A) {
    $start = Find-ZipStart $Path
    $probe = Join-Path $Work ("verify_" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".love")
    $fs = [IO.File]::OpenRead($Path); $fs.Seek($start, 'Begin') | Out-Null
    $os = [IO.File]::Create($probe); $fs.CopyTo($os); $fs.Close(); $os.Close()
  }
  $za = [IO.Compression.ZipFile]::OpenRead($probe)
  try {
    foreach ($n in $Need) {
      if ($null -eq $za.GetEntry($n)) {
        $sample = ($za.Entries | Select-Object -First 6 | ForEach-Object { $_.FullName }) -join " | "
        throw "Verify failed: missing '$n'. Entries look like: $sample"
      }
    }
    if ($Marker) {
      $me = $za.GetEntry("main.lua")
      if ($null -eq $me) { throw "Verify failed: main.lua missing" }
      $sr = New-Object IO.StreamReader($me.Open()); $txt = $sr.ReadToEnd(); $sr.Close()
      if (-not $txt.Contains($Marker)) { throw "Verify failed: main.lua lacks $Marker" }
    }
  } finally { $za.Dispose() }
}

function New-FusedExe([string]$RuntimeExe, [string]$LoveFile, [string]$OutExe) {
  $os = [IO.File]::Create($OutExe)
  try {
    $hs = [IO.File]::OpenRead($RuntimeExe); $hs.CopyTo($os); $hs.Close()
    $ls = [IO.File]::OpenRead($LoveFile);   $ls.CopyTo($os); $ls.Close()
  } finally { $os.Close() }
}

function Find-AndroidProject([string]$Root) {
  foreach ($k in @("platform\android", "android", ".")) {
    $p = Join-Path $Root $k
    if (Test-Path (Join-Path $p "app\src\main")) { return (Resolve-Path $p).Path }
  }
  $g = Get-ChildItem $Root -Recurse -Filter "settings.gradle*" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g -and (Test-Path (Join-Path $g.DirectoryName "app\src\main"))) { return $g.DirectoryName }
  return $null
}

try {
  Write-Host "==============" -ForegroundColor Cyan
  Write-Host "  SUBSTRATUM  " -ForegroundColor Cyan
  Write-Host "==============" -ForegroundColor Cyan

  if ($Target -eq "ask") {
    Write-Host "`nSelect build target:"
    Write-Host "  [1] Windows Desktop (standalone fused Substratum.exe)"
    Write-Host "  [2] Android LOVE    (game.love for your android project)"
    $Target = if ((Read-Host "Enter 1 or 2") -eq "2") { "android" } else { "desktop" }
  }

  $Work = Join-Path $env:TEMP ("apot_build_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
  $Game = Join-Path $Work "game"
  New-Item -ItemType Directory -Path $Game -Force | Out-Null
  $RelDir = Get-Release

  # ---- locate the game (read-only input) ----
  $src = $null
  $searchDir = if ($GameDir) { $GameDir } else { $ScriptDir }
  if (Test-Path -PathType Leaf $searchDir) { $src = $searchDir }
  else {
    $loveFile = (Get-ChildItem $searchDir -Filter *.love -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    foreach ($c in @((Join-Path $searchDir "apotheosisEngine.exe"), $loveFile, (Join-Path $searchDir "main.lua"))) {
      if ($c -and (Test-Path $c)) {
        $src = if ((Split-Path $c -Leaf) -eq "main.lua") { Split-Path $c -Parent } else { $c }
        break
      }
    }
  }
  if (-not $src) { throw "No apotheosisEngine.exe / .love / main.lua found next to this script." }
  Step "Game source: $src"

  if (Test-Path -PathType Container $src) { Copy-Item (Join-Path $src "*") $Game -Recurse -Force }
  elseif ($src -like "*.love") { [IO.Compression.ZipFile]::ExtractToDirectory($src, $Game) }
  else {
    $start = Find-ZipStart $src
    Step "Archive begins at byte $start"
    $origLove = Join-Path $Work "orig.love"
    $fs = [IO.File]::OpenRead($src); $fs.Seek($start, 'Begin') | Out-Null
    $os = [IO.File]::Create($origLove); $fs.CopyTo($os); $fs.Close(); $os.Close()
    [IO.Compression.ZipFile]::ExtractToDirectory($origLove, $Game)
  }
  Step "Game tree extracted."

  # ---- baseline: main hook + shared mods ----
  Apply-UnifiedPatch (Join-Path $RelDir "patches\main.lua.patch") $Game
  $gameMods = Join-Path $Game "mods"
  if (Test-Path $gameMods) { Remove-Item $gameMods -Recurse -Force }
  Copy-Item (Join-Path $RelDir "mods") $gameMods -Recurse -Force
  Step "Baseline mods copied."

  $need = @("mods/init.lua", "mods/api.lua")
  if ($Target -eq "desktop") {
    # android files are never copied; this only guards a pre-split repo layout
    Remove-Item (Join-Path $gameMods "android.lua") -Force -ErrorAction SilentlyContinue
  } else {
    $andMods = Join-Path $RelDir "$AndroidDir\mods"
    if (Test-Path $andMods) {
      Copy-Item (Join-Path $andMods "*") $gameMods -Recurse -Force
      Step "Android overlay copied ($AndroidDir\mods)."
    }
    $andPatch = Join-Path $RelDir "$AndroidDir\patches\android.patch"
    if (-not (Test-Path $andPatch)) { $andPatch = Join-Path $RelDir "patches\android.patch" }
    if (Test-Path $andPatch) { Apply-UnifiedPatch $andPatch $Game }
    $stub = @'
local noop = setmetatable({}, { __index = function() return function() return false end end })
return noop
'@
    [IO.File]::WriteAllText((Join-Path $Game "luasteam.lua"), $stub, (New-Object System.Text.UTF8Encoding($false)))
    Step "luasteam stub written."
    $need += "luasteam.lua"
    if (Test-Path (Join-Path $gameMods "android.lua")) { $need += "mods/android.lua" }
  }

  $PatchedLove = Join-Path $Work "patched.love"
  New-NormalizedZip $Game $PatchedLove
  Test-LoveZip $PatchedLove $need $MARKER
  Step "Patched archive verified ($([math]::Round((Get-Item $PatchedLove).Length/1MB,1)) MB)."

  $OutDir = Resolve-OutDir
  New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

  if ($Target -eq "android") {
    $outLove = Join-Path $OutDir "game.love"
    Copy-Item $PatchedLove $outLove -Force
    Write-Host "`n[SUCCESS] Android package: $outLove" -ForegroundColor Green
    if ($FetchAndroid -and -not $AndroidSrc) {
      New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
      $azip = Join-Path $CacheDir "love-11.5-android-src.zip"
      if (-not (Test-Path $azip)) { Step "Downloading LOVE 11.5 android source..."; Invoke-Download $LoveAndroidUrl $azip }
      $aext = Join-Path $CacheDir "android-src"
      if (-not (Test-Path $aext)) { [IO.Compression.ZipFile]::ExtractToDirectory($azip, $aext) }
      $root = (Get-ChildItem $aext -Directory | Select-Object -First 1).FullName
      $AndroidSrc = Find-AndroidProject $root
      if (-not $AndroidSrc) { Write-Host "[i] Could not locate the gradle project inside the source zip." -ForegroundColor Yellow; $AndroidSrc = "" }
    }
    if ($AndroidSrc) {
      $proj = if (Test-Path (Join-Path $AndroidSrc "app\src\main")) { $AndroidSrc } else { Find-AndroidProject $AndroidSrc }
      if ($proj) {
        $assets = Join-Path $proj "app\src\main\assets"
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
        Copy-Item $outLove (Join-Path $assets "game.love") -Force
        Write-Host "Copied to $assets\game.love" -ForegroundColor Yellow
        Write-Host "Next: cd $proj ; .\gradlew assembleDebug" -ForegroundColor Yellow
      } else {
        Copy-Item $outLove (Join-Path $AndroidSrc "game.love") -Force
        Write-Host "Copied to $AndroidSrc\game.love (place it in app/src/main/assets yourself)." -ForegroundColor Yellow
      }
    } else {
      Write-Host "Put game.love in your android project's app/src/main/assets/, then gradle build." -ForegroundColor Yellow
      Write-Host "or run it with LÖVE for Android (11.5)" -ForegroundColor Yellow
    }
  }
  else {
    $rt = Get-LoveRuntime
    $dest = Join-Path $OutDir "Substratum"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item (Join-Path $rt "*") $dest -Recurse -Force

    $fused = Join-Path $dest "Substratum.exe"
    New-FusedExe (Join-Path $rt "love.exe") $PatchedLove $fused
    Test-LoveZip $fused $need $MARKER
    Step "Fused exe verified."

    $lovec = Join-Path $rt "lovec.exe"
    if (Test-Path $lovec) {
      $console = Join-Path $dest "Substratum-console.exe"
      New-FusedExe $lovec $PatchedLove $console
      Step "Console build made (shows print output)."
    }
    Remove-Item (Join-Path $dest "love.exe") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dest "lovec.exe") -Force -ErrorAction SilentlyContinue

    Write-Host "`n[SUCCESS] Standalone build: $fused" -ForegroundColor Green
    Write-Host "Run Substratum.exe (or Substratum-console.exe to watch mod prints)." -ForegroundColor Yellow
    Write-Host "Steam untouched; saves still in %APPDATA%\apot01." -ForegroundColor Yellow
    Write-Host "or you can replace original with new one" -ForegroundColor Yellow
  }
  exit 0
}
catch {
  Write-Host "`n[BUILD FAILED] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Nothing outside out/ and %LOCALAPPDATA%\Substratum was written." -ForegroundColor Yellow
  exit 1
}
finally {
  if ($Work -and (Test-Path $Work)) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
}