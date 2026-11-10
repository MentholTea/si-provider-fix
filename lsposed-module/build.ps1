<#
.SYNOPSIS
    Build and sign the SI Provider Fix LSPosed module.

.DESCRIPTION
    Toolchain paths come from parameters, then environment variables, then common defaults.
    Signing uses a stable keystore when one is configured; see README.md.

.PARAMETER AndroidSdk
    Android SDK root. Defaults to $env:ANDROID_SDK_ROOT / $env:ANDROID_HOME.

.PARAMETER JavaHome
    JDK root. Defaults to $env:JAVA_HOME.

.PARAMETER Keystore
    Keystore file used for signing. Defaults to keystore.properties or <repo>/release.keystore.

.EXAMPLE
    pwsh -File build.ps1 -AndroidSdk C:\Android\sdk -JavaHome C:\jdk-21
#>
param(
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$Keystore,
    [string]$StorePass,
    [string]$KeyPass,
    [string]$KeyAlias
)

$ErrorActionPreference = 'Stop'

# The project lives under a non-ASCII path; aapt2 on Windows cannot open such paths,
# so everything is mirrored into an ASCII staging directory first.
$srcRoot = $PSScriptRoot
$root = Join-Path $env:TEMP 'si-provider-fix-build'

if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT; if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_HOME } }
if (-not $AndroidSdk) { throw 'Android SDK not found. Pass -AndroidSdk or set ANDROID_SDK_ROOT.' }
if (-not (Test-Path $AndroidSdk)) { throw "Android SDK not found: $AndroidSdk" }

if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
if (-not $JavaHome) { throw 'JDK not found. Pass -JavaHome or set JAVA_HOME.' }
if (-not (Test-Path $JavaHome)) { throw "JDK not found: $JavaHome" }

$sdk = $AndroidSdk
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $bt) { throw "no build-tools under $sdk" }
$bt = $bt.FullName

$platform = Get-ChildItem (Join-Path $sdk 'platforms') -Directory |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $platform) { throw "no platform under $sdk" }

$java = Join-Path $JavaHome 'bin\java.exe'
$javac = Join-Path $JavaHome 'bin\javac.exe'
$jarTool = Join-Path $JavaHome 'bin\jar.exe'
$keytool = Join-Path $JavaHome 'bin\keytool.exe'
$androidJar = Join-Path $platform.FullName 'android.jar'
$d8Jar = Join-Path $bt 'lib\d8.jar'
$apksignerJar = Join-Path $bt 'lib\apksigner.jar'

if (Test-Path $root) { Remove-Item $root -Recurse -Force }
New-Item -ItemType Directory -Force -Path $root | Out-Null
Copy-Item (Join-Path $srcRoot 'AndroidManifest.xml') $root -Force
Copy-Item (Join-Path $srcRoot 'res') $root -Recurse -Force
Copy-Item (Join-Path $srcRoot 'src') $root -Recurse -Force
Copy-Item (Join-Path $srcRoot 'stubs') $root -Recurse -Force
Copy-Item (Join-Path $srcRoot 'assets') $root -Recurse -Force

$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $build 'stubs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $build 'classes') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $build 'dex') | Out-Null

Write-Host '== 1. compile xposed stubs =='
$stubFiles = Get-ChildItem (Join-Path $root 'stubs') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& $javac -encoding UTF-8 --release 8 -nowarn -cp $androidJar -d (Join-Path $build 'stubs') $stubFiles
if ($LASTEXITCODE -ne 0) { throw 'stub compile failed' }

Write-Host '== 2. compile module =='
$srcFiles = Get-ChildItem (Join-Path $root 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$cp = "$androidJar;$(Join-Path $build 'stubs')"
& $javac -encoding UTF-8 --release 8 -nowarn -cp $cp -d (Join-Path $build 'classes') $srcFiles
if ($LASTEXITCODE -ne 0) { throw 'module compile failed' }

Write-Host '== 3. dex =='
& $jarTool cf (Join-Path $build 'classes.jar') -C (Join-Path $build 'classes') .
if ($LASTEXITCODE -ne 0) { throw 'jar failed' }
& $java -cp $d8Jar com.android.tools.r8.D8 --release --min-api 29 --lib $androidJar --output (Join-Path $build 'dex') (Join-Path $build 'classes.jar')
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }

Write-Host '== 4. aapt2 compile =='
& (Join-Path $bt 'aapt2.exe') compile --dir (Join-Path $root 'res') -o (Join-Path $build 'res.zip')
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }

Write-Host '== 5. aapt2 link =='
$unsigned = Join-Path $build 'base-unsigned.apk'
& (Join-Path $bt 'aapt2.exe') link -o $unsigned -I $androidJar --manifest (Join-Path $root 'AndroidManifest.xml') --min-sdk-version 29 --target-sdk-version 34 --version-code 20 --version-name 2.0 (Join-Path $build 'res.zip')
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

Write-Host '== 6. add dex + assets =='
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsigned, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $dexEntry = $zip.CreateEntry('classes.dex', [System.IO.Compression.CompressionLevel]::Optimal)
    $dexStream = $dexEntry.Open()
    $dexBytes = [System.IO.File]::ReadAllBytes((Join-Path $build 'dex\classes.dex'))
    $dexStream.Write($dexBytes, 0, $dexBytes.Length)
    $dexStream.Close()

    $initEntry = $zip.CreateEntry('assets/xposed_init', [System.IO.Compression.CompressionLevel]::Optimal)
    $initStream = $initEntry.Open()
    $initBytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'assets\xposed_init'))
    $initStream.Write($initBytes, 0, $initBytes.Length)
    $initStream.Close()
} finally {
    $zip.Dispose()
}

Write-Host '== 7. zipalign =='
$aligned = Join-Path $build 'base-aligned.apk'
& (Join-Path $bt 'zipalign.exe') -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

Write-Host '== 8. signing key =='
# A stable key matters: Android refuses to update an installed app whose signature changed,
# so re-building with a fresh throwaway key would force an uninstall every time.
#
# Resolution order:
#   1. -Keystore / -StorePass / -KeyPass / -KeyAlias parameters
#   2. keystore.properties next to this script (never commit it)
#   3. the repository's release keystore at <repo>/release.keystore
#   4. a freshly generated throwaway key in the build dir (unsigned-for-release, warns)
$props = Join-Path $srcRoot 'keystore.properties'
if (-not $Keystore -and (Test-Path $props)) {
    $cfg = @{}
    Get-Content $props | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
    }
    if (-not $Keystore)   { $Keystore   = $cfg['storeFile'] }
    if (-not $StorePass)  { $StorePass  = $cfg['storePassword'] }
    if (-not $KeyPass)    { $KeyPass    = $cfg['keyPassword'] }
    if (-not $KeyAlias)   { $KeyAlias   = $cfg['keyAlias'] }
    # storeFile is relative to the properties file, not to the process working directory
    if ($Keystore -and -not [System.IO.Path]::IsPathRooted($Keystore)) {
        $Keystore = Join-Path $srcRoot $Keystore
    }
    $Keystore = [System.IO.Path]::GetFullPath($Keystore)
}

if (-not $Keystore) {
    $repoRoot = Split-Path $srcRoot -Parent
    $candidate = Join-Path $repoRoot 'release.keystore'
    if (Test-Path $candidate) { $Keystore = $candidate }
}

if ($Keystore) {
    if (-not (Test-Path $Keystore)) { throw "keystore not found: $Keystore" }
    if (-not $StorePass) { throw 'storePassword is required when signing with a keystore' }
    if (-not $KeyAlias)  { throw 'keyAlias is required when signing with a keystore' }
    if (-not $KeyPass)   { $KeyPass = $StorePass }
    Write-Host "   using $Keystore (alias $KeyAlias)"
} else {
    Write-Host '   WARNING: no release keystore configured, generating a throwaway one.'
    Write-Host '   The resulting APK is signed with a random key; installing over an existing'
    Write-Host '   build will fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.'
    Write-Host '   Create release.keystore (see README) for a stable signature.'
    $Keystore = Join-Path $build 'debug.keystore'
    $StorePass = 'android'
    $KeyPass = 'android'
    $KeyAlias = 'siproviderfix'
    if (-not (Test-Path $Keystore)) {
        & $keytool -genkeypair -keystore $Keystore -storepass $StorePass -keypass $KeyPass -alias $KeyAlias -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=SiProviderFix, OU=Android, O=Local, C=CN' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
    }
}

Write-Host '== 9. sign =='
$outApk = Join-Path $root 'si-provider-fix.apk'
if (Test-Path $outApk) { Remove-Item $outApk -Force }
& $java -jar $apksignerJar sign --ks $Keystore --ks-key-alias $KeyAlias --ks-pass "pass:$StorePass" --key-pass "pass:$KeyPass" --out $outApk $aligned
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }

Write-Host '== 10. verify =='
& $java -jar $apksignerJar verify --print-certs $outApk
Copy-Item $outApk (Join-Path $srcRoot 'si-provider-fix.apk') -Force
Get-Item (Join-Path $srcRoot 'si-provider-fix.apk') | Select-Object FullName, Length

