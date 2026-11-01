# setup.ps1: installs everything the engine needs into %LOCALAPPDATA%\FreeVoiceConvert (Windows 10/11, 64-bit).
# The installer runs this (a window shows the progress); the app runs it again if anything is missing.
#   uv (Astral) -> Python 3.11 -> torch (CUDA when an NVIDIA card is present) + the packages -> Seed-VC -> every model.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Engine = Split-Path -Parent $MyInvocation.MyCommand.Path
$pins = @{}
Get-Content (Join-Path $Engine "PINS") | ForEach-Object { if ($_ -match "^(\w+)=(.+)$") { $pins[$Matches[1]] = $Matches[2].Trim() } }
$FvcHome = if ($env:FVC_HOME) { $env:FVC_HOME } else { Join-Path $env:LOCALAPPDATA "FreeVoiceConvert" }
$env:FVC_HOME = $FvcHome
New-Item -ItemType Directory -Force -Path $FvcHome | Out-Null
Set-Location $FvcHome
function P($pct, $msg) { Write-Output ("@{""pct"": $pct, ""msg"": ""$msg""}") }
$env:UV_PYTHON_INSTALL_DIR = Join-Path $FvcHome "python"
$env:UV_CACHE_DIR = Join-Path $FvcHome "uv-cache"
$uv = Join-Path $FvcHome "bin\uv.exe"
$py = Join-Path $FvcHome "venv\Scripts\python.exe"

if (-not (Test-Path $uv)) {
  P 2 "downloading uv (the Python installer)"
  New-Item -ItemType Directory -Force -Path (Join-Path $FvcHome "bin") | Out-Null
  $zip = Join-Path $FvcHome "uv.zip"
  Invoke-WebRequest "https://github.com/astral-sh/uv/releases/download/$($pins.UV_VERSION)/uv-x86_64-pc-windows-msvc.zip" -OutFile $zip
  Expand-Archive $zip -DestinationPath (Join-Path $FvcHome "bin") -Force
  Remove-Item $zip
}
if (-not (Test-Path $py)) {
  P 6 "installing Python $($pins.PYTHON)"
  & $uv venv -q --python $pins.PYTHON --python-preference only-managed venv
  if ($LASTEXITCODE) { throw "uv venv failed" }
}
$index = "https://download.pytorch.org/whl/cpu"
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { $index = "https://download.pytorch.org/whl/cu124"; P 10 "NVIDIA card found: CUDA torch" }
P 12 "installing torch $($pins.TORCH)"
& $uv pip install -q --python $py "torch==$($pins.TORCH)" "torchaudio==$($pins.TORCH)" --index-url $index
if ($LASTEXITCODE) { throw "torch install failed" }
P 30 "installing the audio packages"
& $uv pip install -q --python $py -r (Join-Path $Engine "requirements.txt")
if ($LASTEXITCODE) { throw "package install failed" }
$commitFile = Join-Path $FvcHome "seed-vc\.commit"
if (-not (Test-Path $commitFile) -or ((Get-Content $commitFile) -ne $pins.SEEDVC_COMMIT)) {
  P 40 "downloading Seed-VC"
  if (Test-Path "seed-vc") { Remove-Item -Recurse -Force "seed-vc" }
  $zip = Join-Path $FvcHome "seedvc.zip"
  Invoke-WebRequest "https://github.com/Plachtaa/seed-vc/archive/$($pins.SEEDVC_COMMIT).zip" -OutFile $zip
  Expand-Archive $zip -DestinationPath $FvcHome -Force
  Remove-Item $zip
  Rename-Item (Join-Path $FvcHome "seed-vc-$($pins.SEEDVC_COMMIT)") "seed-vc"
  Set-Content $commitFile $pins.SEEDVC_COMMIT
}
P 45 "downloading the models (about 2.5 GB)"
& $py (Join-Path $Engine "fvc.py") fetch
exit $LASTEXITCODE
