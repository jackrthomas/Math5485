# Render the public and private sites, then publish the public one to GitHub Pages.
#
#   .\publish.ps1              render both, check, publish _book/ to gh-pages
#   .\publish.ps1 -NoPublish   render both and check, but don't publish
#
# Only _book/ (public) is published. _book-private/ is git-ignored and never leaves this machine.

param([switch]$NoPublish)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Step($name, [scriptblock]$cmd) {
    Write-Host "`n== $name" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { Write-Host "`n$name failed (exit $LASTEXITCODE); nothing published." -ForegroundColor Red; exit $LASTEXITCODE }
}

Step 'Public render (_book/)'          { quarto render }
Step 'Private render (_book-private/)' { quarto render --profile private }

# safety net: draft hints/solutions must never reach the public site
Write-Host "`n== Checking _book/ for draft answers" -ForegroundColor Cyan
$leaks = Get-ChildItem _book -Recurse -Include *.html, *.json |
    Select-String -Pattern 'exercise-(solution|hint)[^"]*\bdraft\b' -List
if ($leaks) {
    Write-Host 'Draft answers found in the public site; nothing published:' -ForegroundColor Red
    $leaks | ForEach-Object { Write-Host "  $($_.Path)" }
    exit 1
}
Write-Host 'None found.'

if ($NoPublish) { Write-Host "`nRendered both sites; skipped publishing (-NoPublish)." -ForegroundColor Green; exit 0 }

Step 'Publish _book/ to gh-pages' { quarto publish gh-pages --no-render --no-prompt }

Write-Host "`nDone: public site published, private site in _book-private/." -ForegroundColor Green
