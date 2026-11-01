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
# Fetch: continues a broken download from its last byte (curl.exe is in every Windows 10/11); a server that cannot
# continue gets a fresh download.
function Fetch($file, $url) {
  if ((Test-Path $file) -and (Test-Path "$file.done")) { return }  # finished before: never fetched twice
  & curl.exe -fL --retry 10 --retry-delay 3 -C - -o $file $url
  if ($LASTEXITCODE) { Remove-Item $file -ErrorAction SilentlyContinue; & curl.exe -fL --retry 10 --retry-delay 3 -o $file $url }
  if ($LASTEXITCODE) { throw "download failed: $url (it continues at the next start)" }
  New-Item -ItemType File -Force -Path "$file.done" | Out-Null
}
$env:UV_PYTHON_INSTALL_DIR = Join-Path $FvcHome "python"
$env:UV_CACHE_DIR = Join-Path $FvcHome "uv-cache"
$uv = Join-Path $FvcHome "bin\uv.exe"
$py = Join-Path $FvcHome "venv\Scripts\python.exe"

if (-not (Test-Path $uv)) {
  P 2 "downloading uv (the Python installer)"
  New-Item -ItemType Directory -Force -Path (Join-Path $FvcHome "bin") | Out-Null
  $zip = Join-Path $FvcHome "uv.zip"
  Fetch $zip "https://github.com/astral-sh/uv/releases/download/$($pins.UV_VERSION)/uv-x86_64-pc-windows-msvc.zip"
  Expand-Archive $zip -DestinationPath (Join-Path $FvcHome "bin") -Force
  Remove-Item $zip, "$zip.done"
}
if (-not (Test-Path $py)) {
  P 6 "installing Python $($pins.PYTHON)"
  & $uv venv -q --python $pins.PYTHON --python-preference only-managed venv
  if ($LASTEXITCODE) { throw "uv venv failed" }
}
& $py -c "import torch,torchaudio,sys; sys.exit(torch.__version__.split('+')[0] != '$($pins.TORCH)')" 2>$null
if ($LASTEXITCODE -eq 0) { P 20 "torch $($pins.TORCH) is here" } else {
$flavour = "cpu"
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { $flavour = "cu124"; P 10 "NVIDIA card found: CUDA torch (about 2.5 GB)" }
P 12 "downloading torch $($pins.TORCH)"
# the two big wheels by curl, so a broken download continues at the next start; uv then installs them
$wheels = Join-Path $FvcHome "wheels"; New-Item -ItemType Directory -Force -Path $wheels | Out-Null
$t1 = "torch-$($pins.TORCH)+$flavour-cp311-cp311-win_amd64.whl"; $t2 = "torchaudio-$($pins.TORCH)+$flavour-cp311-cp311-win_amd64.whl"
foreach ($w in @($t1, $t2)) { Fetch (Join-Path $wheels $w) ("https://download.pytorch.org/whl/$flavour/" + $w.Replace("+", "%2B")) }
P 20 "installing torch $($pins.TORCH)"
& $uv pip install -q --python $py (Join-Path $wheels $t1) (Join-Path $wheels $t2)
if ($LASTEXITCODE) { throw "torch install failed" }
Remove-Item -Recurse -Force $wheels
}
P 30 "installing the audio packages"
& $uv pip install -q --python $py -r (Join-Path $Engine "requirements.txt")
if ($LASTEXITCODE) { throw "package install failed" }
$commitFile = Join-Path $FvcHome "seed-vc\.commit"
if (-not (Test-Path $commitFile) -or ((Get-Content $commitFile) -ne $pins.SEEDVC_COMMIT)) {
  P 40 "downloading Seed-VC"
  if (Test-Path "seed-vc") { Remove-Item -Recurse -Force "seed-vc" }
  $zip = Join-Path $FvcHome "seedvc-$($pins.SEEDVC_COMMIT).zip"
  # curl.exe (in every Windows 10/11) with -C -: a broken download continues from its last byte at the next start
  Fetch $zip "https://github.com/Plachtaa/seed-vc/archive/$($pins.SEEDVC_COMMIT).zip"
  Expand-Archive $zip -DestinationPath $FvcHome -Force
  Remove-Item $zip, "$zip.done"
  Rename-Item (Join-Path $FvcHome "seed-vc-$($pins.SEEDVC_COMMIT)") "seed-vc"
  Set-Content $commitFile $pins.SEEDVC_COMMIT
}
P 45 "downloading the models (about 2.5 GB)"
& $py (Join-Path $Engine "fvc.py") fetch
exit $LASTEXITCODE
