[CmdletBinding()]
param(
    [string]$AssetsDirectory,
    [ValidateSet('meop/PSNWDL', 'meop/WinEnvEdit')][string]$Repository,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AssetsDirectory) { $AssetsDirectory = Join-Path $repoRoot 'out/downloads' }
New-Item -ItemType Directory -Force -Path $AssetsDirectory | Out-Null
$products = @(
    @{
        id = 'psnwdl'; product = 'PSNWDL'; repository = 'meop/PSNWDL'
        asset = 'psnwdl-{version}-windows-{arch}-portable.zip'; executable = 'PSNWDL.exe'
        description = 'Browse, download and manage official PlayStation game updates and firmware, with RPCS3 library integration.'
        notes = 'Requires the Microsoft Edge WebView2 Runtime (normally present on Windows 11).'
    },
    @{
        id = 'winenvedit'; product = 'WinEnvEdit'; repository = 'meop/WinEnvEdit'
        asset = 'WinEnvEdit-{arch}.zip'; executable = 'WinEnvEdit.exe'
        description = 'Edit Windows user and system environment variables with path management, import/export and undo history.'
        notes = 'Requires Windows 11 or later.'
    }
)
$pending = @()
if ($Version -and -not $Repository) { throw 'A specific version requires a repository.' }
if ($Repository) { $products = @($products | Where-Object repository -EQ $Repository) }
foreach ($product in $products) {
    $endpoint = if ($Version) { "repos/$($product.repository)/releases/tags/v$Version" } else { "repos/$($product.repository)/releases/latest" }
    $releaseJson = & gh api $endpoint
    if ($LASTEXITCODE -ne 0) { throw "Could not read release for $($product.repository)." }
    $release = $releaseJson | ConvertFrom-Json
    $releaseVersion = $release.tag_name -replace '^v', ''
    if ($release.draft -or $release.prerelease -or $releaseVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Expected published stable release for $($product.repository)."
    }
    $manifestPath = Join-Path $repoRoot "bucket/$($product.id).json"
    if (Test-Path -LiteralPath $manifestPath) {
        $previous = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([version]$releaseVersion -lt [version]$previous.version) { throw "Refusing downgrade of $($product.id)." }
    }
    $architecture = [ordered]@{}
    $autoupdate = [ordered]@{}
    foreach ($arch in @('x64', 'arm64')) {
        $assetName = $product.asset.Replace('{version}', $releaseVersion).Replace('{arch}', $arch)
        $assets = @($release.assets | Where-Object name -CEQ $assetName)
        if ($assets.Count -ne 1) { throw "Expected exactly one release asset: $assetName" }
        $asset = $assets[0]
        $expectedUrl = "https://github.com/$($product.repository)/releases/download/$($release.tag_name)/$assetName"
        if ($asset.browser_download_url -cne $expectedUrl) { throw "Unexpected download URL: $assetName" }
        # Version-specific cache prevents WinEnvEdit's reused asset names from colliding.
        $cacheDir = Join-Path $AssetsDirectory "$($product.id)/$releaseVersion"
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        $assetPath = Join-Path $cacheDir $assetName
        if (-not (Test-Path -LiteralPath $assetPath)) {
            & gh release download $release.tag_name --repo $product.repository --pattern $assetName --dir $cacheDir
            if ($LASTEXITCODE -ne 0) { throw "Could not download $assetName" }
        }
        if ((Get-Item -LiteralPath $assetPath).Length -ne $asset.size) { throw "Asset size mismatch: $assetName" }
        $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($asset.PSObject.Properties['digest'] -and $asset.digest -and $asset.digest -cne "sha256:$hash") {
            throw "GitHub asset digest mismatch: $assetName"
        }
        $zip = [IO.Compression.ZipFile]::OpenRead($assetPath)
        try {
            if (-not $zip.GetEntry($product.executable)) { throw "Missing root executable: $assetName" }
        } finally { $zip.Dispose() }
        $key = if ($arch -eq 'x64') { '64bit' } else { 'arm64' }
        $architecture[$key] = [ordered]@{ url = $expectedUrl; hash = $hash }
        $pattern = $product.asset.Replace('{version}', '$version').Replace('{arch}', $arch)
        $autoupdate[$key] = @{ url = "https://github.com/$($product.repository)/releases/download/v`$version/$pattern" }
    }
    $manifest = [ordered]@{
        version = $releaseVersion
        description = $product.description
        homepage = "https://github.com/$($product.repository)"
        license = 'MIT'
        notes = $product.notes
        architecture = $architecture
        shortcuts = ,@($product.executable, $product.product)
        checkver = @{ github = "https://github.com/$($product.repository)" }
        autoupdate = @{ architecture = $autoupdate }
    }
    $pending += @{ Path = $manifestPath; Json = ($manifest | ConvertTo-Json -Depth 10) }
    Write-Output "Verified $($product.id) $releaseVersion, x64 and ARM64 assets."
}
# Write only after all selected products pass every check.
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'bucket') | Out-Null
foreach ($item in $pending) {
    [IO.File]::WriteAllText($item.Path, ($item.Json.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}
