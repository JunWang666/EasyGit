# Packs and signs the Explorer context menu package for release builds.
#
#   flutter build windows --release
#   powershell -File windows\shell_extension\package.ps1 -Pfx cert.pfx -Password ****
#
# The certificate's subject must equal the manifest's Publisher. Pass
# -Publisher to rewrite it (for example "CN=Your Name, O=Your Company").
# Users need the certificate trusted (a CA-issued code signing certificate,
# or a self-signed one imported into "Trusted People") to install the .msix.
param(
  [Parameter(Mandatory = $true)][string]$Pfx,
  [string]$Password = '',
  [string]$Publisher = '',
  [string]$Bundle = "$PSScriptRoot\..\..\build\windows\x64\runner\Release"
)
$ErrorActionPreference = 'Stop'

$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $sdk) { throw 'makeappx.exe not found. Install the Windows 10/11 SDK.' }
$bin = $sdk.DirectoryName

$shell = Join-Path (Resolve-Path $Bundle) 'shell'
$stage = Join-Path $env:TEMP "easygit-menu-$([guid]::NewGuid())"
New-Item -ItemType Directory $stage | Out-Null
try {
  Copy-Item "$shell\AppxManifest.xml", "$shell\logo.png" $stage
  if ($Publisher) {
    $m = Join-Path $stage 'AppxManifest.xml'
    (Get-Content $m -Raw) -replace 'Publisher="CN=EasyGit"', "Publisher=`"$Publisher`"" |
      Set-Content $m -Encoding UTF8
  }
  $msix = Join-Path $shell 'EasyGit.ExplorerMenu.msix'
  & "$bin\makeappx.exe" pack /o /d $stage /p $msix /nv
  if ($LASTEXITCODE) { throw "makeappx failed ($LASTEXITCODE)" }
  $sign = @('sign', '/fd', 'SHA256', '/f', $Pfx)
  if ($Password) { $sign += @('/p', $Password) }
  & "$bin\signtool.exe" @sign $msix
  if ($LASTEXITCODE) { throw "signtool failed ($LASTEXITCODE)" }
  Write-Host "Created $msix"
} finally {
  Remove-Item -Recurse -Force $stage
}
