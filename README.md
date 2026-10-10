# meop Scoop bucket

Windows packages for [PSNWDL](https://github.com/meop/PSNWDL) and
[WinEnvEdit](https://github.com/meop/WinEnvEdit), maintained by their publisher.

Install [Scoop](https://scoop.sh), then:

```powershell
scoop bucket add meop https://github.com/meop/scoop-bucket
scoop install meop/psnwdl
scoop install meop/winenvedit
```

PSNWDL requires Microsoft's WebView2 Runtime. WinEnvEdit requires Windows 11.
Both packages use the official portable release ZIPs and support x64 and ARM64.
Only Windows x64 runtime has been smoke-tested so far.

Update with `scoop update` followed by `scoop update psnwdl winenvedit`.
Uninstall with `scoop uninstall psnwdl winenvedit`. Removing a package does not
erase the application's separately stored user data or intentionally edited
Windows environment variables.

## Maintenance

Each app's release pipeline calls this bucket's reusable GitHub Actions workflow
after publishing a stable release. A manual bucket workflow can also refresh both
latest stable releases. There is no scheduled polling. It downloads both architectures, verifies release
asset sizes and available GitHub SHA256 digests, checks ZIP executable layout,
then commits changed manifests. Drafts, prereleases and version downgrades are
rejected. Each app's SCOOP_BUCKET_SSH_KEY Actions secret holds a deploy key with
write access only to this bucket. No personal access token is needed.

```powershell
./scripts/Update-Manifests.ps1
```

Requires PowerShell 7 and GitHub CLI. Downloads are cached in ignored `out/`.
The manifests also contain Scoop checkver/autoupdate metadata. Manual edits to
package metadata should be made in the updater because it regenerates manifests.

Public Games/Extras inclusion may be requested later. The package names remain
`psnwdl` and `winenvedit`; this bucket will remain maintained during a transition.
