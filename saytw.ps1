$ErrorActionPreference = "Stop"
$Version = if ($env:SAYT_VERSION) { $env:SAYT_VERSION } else { "0.0.6" }
$CacheDir = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "sayt"
} elseif ($env:XDG_CACHE_HOME) {
    Join-Path $env:XDG_CACHE_HOME "sayt"
} else {
    Join-Path $env:HOME ".cache/sayt"
}

# Detect Arch
if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    $BinName = "sayt-windows-x64.exe"
} elseif ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $BinName = "sayt-windows-arm64.exe"
} else {
    Write-Error "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE"
    exit 1
}

$Binary = Join-Path $CacheDir $BinName
$SaytLink = Join-Path $CacheDir "sayt.exe"

if (-not (Test-Path $Binary)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    Write-Host "Downloading sayt v$Version ($BinName)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/bonitao/sayt/releases/download/$Version/$BinName" -OutFile $Binary -UseBasicParsing
    
    # Create/Update 'symlink' (copy for simplicity on Windows or just rely on direct call)
    Copy-Item -Path $Binary -Destination $SaytLink -Force
}

& $Binary @args
exit $LASTEXITCODE