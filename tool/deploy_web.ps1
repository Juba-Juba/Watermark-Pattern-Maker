param([string]$Flutter = 'D:\FlutterSdk\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    & $Flutter build web --release --base-href / --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
    & (Join-Path $PSScriptRoot 'prepare_web.ps1')
    $target = Join-Path $project 'output\pages'
    if (-not (Test-Path (Join-Path $target '.git'))) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        git -C $target init -b gh-pages
        git -C $target remote add origin https://github.com/Juba-Juba/Watermark-Pattern-Maker.git
        git -C $target fetch origin gh-pages
        if ($LASTEXITCODE -eq 0) { git -C $target reset --hard origin/gh-pages }
    }
    $actual = (git -C $target rev-parse --show-toplevel).Trim().Replace('/', '\')
    if ($actual -ne $target) { throw 'Unexpected deployment checkout path' }
    git -C $target config user.name Juba-Juba
    git -C $target config user.email elprince.dokdok@gmail.com
    git -C $target rm -r --ignore-unmatch . | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $project 'build\web') -Force | Copy-Item -Destination $target -Recurse -Force
    Set-Content -LiteralPath (Join-Path $target 'CNAME') -Value 'watermark.juba-tech.store' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $target '.nojekyll') -Value '' -Encoding ascii
    git -C $target add -A
    git -C $target diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $target commit -m 'Deploy Watermark Pattern Maker web'
        if ($LASTEXITCODE -ne 0) { throw 'Deployment commit failed' }
    }
    git -C $target push -u origin gh-pages
    if ($LASTEXITCODE -ne 0) { throw 'Deployment push failed; check GitHub sign-in' }
} finally { Pop-Location }
