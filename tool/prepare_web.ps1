param([string]$BuildDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\web'))
$ErrorActionPreference = 'Stop'
$main = Join-Path $BuildDirectory 'main.dart.js'
$hash = (Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash.ToLowerInvariant()
$entrypoint = "main.$($hash.Substring(0, 16)).js"
Copy-Item -LiteralPath $main -Destination (Join-Path $BuildDirectory $entrypoint) -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($name in @('index.html', 'flutter_bootstrap.js')) {
    $path = Join-Path $BuildDirectory $name
    $content = [System.IO.File]::ReadAllText($path)
    $content = $content.Replace('"mainJsPath":"main.dart.js"', '"mainJsPath":"' + $entrypoint + '"')
    [System.IO.File]::WriteAllText($path, $content, $utf8)
}
# A retiring worker also updates clients still using the old Flutter bootstrap.
$retire = @'
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil((async () => {
  await Promise.all(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'].map(name => caches.delete(name)));
  await self.registration.unregister();
})()));
'@
[System.IO.File]::WriteAllText((Join-Path $BuildDirectory 'flutter_service_worker.js'), $retire, $utf8)
$version = @{ entrypoint = $entrypoint; sha256 = $hash } | ConvertTo-Json
[System.IO.File]::WriteAllText((Join-Path $BuildDirectory 'version.json'), $version, $utf8)
Write-Output "Versioned web entrypoint: $entrypoint"
