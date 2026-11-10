$ErrorActionPreference = 'Stop'

# The project lives under a non-ASCII path; aapt2 on Windows cannot open such paths,
# so everything is mirrored into an ASCII staging directory first.
$srcRoot = 'D:\000.AI\001.项目\si-provider-fix'
$root = Join-Path $env:TEMP 'si-provider-fix-build'
$sdk = 'D:\000.AI\001.DSH\android-sdk'
$bt = Join-Path $sdk 'build-tools\34.0.0'
$jdk = 'D:\000.AI\001.DSH\toolchain\rea-native\jdk-21.0.12.1+1'
$java = Join-Path $jdk 'bin\java.exe'
$javac = Join-Path $jdk 'bin\javac.exe'
$jarTool = Join-Path $jdk 'bin\jar.exe'
$keytool = Join-Path $jdk 'bin\keytool.exe'
$androidJar = Join-Path $sdk 'platforms\android-35\android.jar'
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
& (Join-Path $bt 'aapt2.exe') link -o $unsigned -I $androidJar --manifest (Join-Path $root 'AndroidManifest.xml') --min-sdk-version 29 --target-sdk-version 34 --version-code 1 --version-name 1.0 (Join-Path $build 'res.zip')
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

Write-Host '== 8. keystore =='
$ks = Join-Path $build 'debug.keystore'
if (-not (Test-Path $ks)) {
    & $keytool -genkeypair -keystore $ks -storepass android -keypass android -alias siproviderfix -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=SiProviderFix, OU=Android, O=Local, C=CN' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
}

Write-Host '== 9. sign =='
$outApk = Join-Path $root 'si-provider-fix.apk'
if (Test-Path $outApk) { Remove-Item $outApk -Force }
& $java -jar $apksignerJar sign --ks $ks --ks-pass pass:android --key-pass pass:android --out $outApk $aligned
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }

Write-Host '== 10. verify =='
& $java -jar $apksignerJar verify --print-certs $outApk
Copy-Item $outApk (Join-Path $srcRoot 'si-provider-fix.apk') -Force
Get-Item (Join-Path $srcRoot 'si-provider-fix.apk') | Select-Object FullName, Length
