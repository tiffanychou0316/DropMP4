$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
py -3.12 -m venv .venv
if ($LASTEXITCODE -ne 0) { throw 'Python 3.12 venv failed' }
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt pyinstaller==6.16.0
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
& .\.venv\Scripts\python.exe -m unittest discover -s tests -p test_receiver.py -v
if ($LASTEXITCODE -ne 0) { throw 'Receiver tests failed' }
$extraData = @()
$sslDirectory = & .\.venv\Scripts\python.exe -c "import ssl, pathlib; print(pathlib.Path(ssl.__file__).parent)"
$runtimeCertificate = Join-Path $sslDirectory 'codex-rejected-cas.pem'
if (Test-Path -LiteralPath $runtimeCertificate) { $extraData = @('--add-data', ($runtimeCertificate + ';.')) }
& .\.venv\Scripts\python.exe -m PyInstaller --noconfirm --onedir --windowed --name DropMP4 @extraData windows_main.py
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
& .\.venv\Scripts\python.exe scripts\collect_licenses.py dist\DropMP4
if ($LASTEXITCODE -ne 0) { throw 'License collection failed' }
& .\.venv\Scripts\python.exe scripts\fetch_dependency_source.py dist\DropMP4\third-party-source
if ($LASTEXITCODE -ne 0) { throw 'LGPL source download failed' }
Write-Host 'Run dist\DropMP4\DropMP4.exe; keep the _internal directory beside it.'
