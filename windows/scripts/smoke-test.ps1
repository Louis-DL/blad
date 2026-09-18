# Starts the published Blad on the build machine and photographs it: once on the welcome
# screen, once with a space open in the editor and once in reading mode. Fails when Blad
# doesn't stay open, and prints why.
param([string]$App = "publish/Blad/Blad.exe", [string]$Out = "screenshots")

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
"@

New-Item -ItemType Directory -Force $Out | Out-Null
$data = Join-Path $env:LOCALAPPDATA "Blad"

function Show-Crash {
    $log = Join-Path $data "crash.log"
    if (Test-Path $log) { Get-Content $log | Write-Host }
    Get-WinEvent -LogName Application -MaxEvents 30 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -in ".NET Runtime", "Application Error" } |
        ForEach-Object { Write-Host $_.Message }
}

function Save-Screen([string]$name) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path $Out "$name.png"))
    $graphics.Dispose(); $bitmap.Dispose()
}

function Start-Blad {
    $process = Start-Process $App -PassThru
    for ($i = 0; $i -lt 30 -and $process.MainWindowHandle -eq 0; $i++) {
        Start-Sleep -Seconds 1
        $process.Refresh()
        if ($process.HasExited) { break }
    }
    Start-Sleep -Seconds 4
    $process.Refresh()
    if ($process.HasExited) {
        Show-Crash
        throw "Blad stopped right after starting (exit code $($process.ExitCode))."
    }
    [Win]::ShowWindow($process.MainWindowHandle, 3) | Out-Null   # maximised
    [Win]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "Blad is open: '$($process.MainWindowTitle)'"
    return $process
}

function Stop-Blad($process) {
    $process.Refresh()
    if ($process.HasExited) {
        Show-Crash
        throw "Blad stopped while it was being used (exit code $($process.ExitCode))."
    }
    Stop-Process $process -Force
    Start-Sleep -Seconds 1
}

# 1. First launch: nothing set up yet.
Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
$blad = Start-Blad
Save-Screen "1-welkom"
Stop-Blad $blad

# 2. A space with a couple of pages, one of them open.
$space = Join-Path $env:RUNNER_TEMP "Vakken\Geschiedenis"
New-Item -ItemType Directory -Force (Join-Path $space "Hoofdstukken") | Out-Null
@"
# De Franse Revolutie

Samenvatting voor het examen van **vrijdag**. Zie ook [[Tijdlijn]] en *hoofdstuk 3*.

## Oorzaken

- Financiële crisis van de staat
- Ideeën van de *Verlichting*
  - Rousseau en Montesquieu
- Slechte oogsten in 1788

## Planning

- [x] Hoofdstuk 1 lezen
- [ ] Tijdlijn afwerken
- [ ] Oefenvragen maken

> Vrijheid, gelijkheid, broederschap.

``````python
def jaar(gebeurtenis):
    return tijdlijn[gebeurtenis]
``````

| Jaar | Gebeurtenis |
|------|-------------|
| 1789 | Bestorming van de Bastille |
| 1793 | Terreur |
"@ | Set-Content -Encoding utf8 (Join-Path $space "Franse Revolutie.md")
"# Tijdlijn`n`n1. 1789`n2. 1793`n3. 1799`n`nTerug naar [[Franse Revolutie]]." |
    Set-Content -Encoding utf8 (Join-Path $space "Tijdlijn.md")
"# Hoofdstuk 3`n`nNotities." | Set-Content -Encoding utf8 (Join-Path $space "Hoofdstukken\Hoofdstuk 3.md")

$page = Join-Path $space "Franse Revolutie.md"
New-Item -ItemType Directory -Force $data | Out-Null
@{
    Spaces     = @($space)
    OpenPages  = @($page, (Join-Path $space "Tijdlijn.md"))
    ActivePage = $page
} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $data "settings.json")

$blad = Start-Blad
Save-Screen "2-bewerken"

# 3. Reading mode (Ctrl+R).
[System.Windows.Forms.SendKeys]::SendWait("^r")
Start-Sleep -Seconds 2
Save-Screen "3-lezen"

# 4. Search (Ctrl+K).
[System.Windows.Forms.SendKeys]::SendWait("{ESC}^k")
Start-Sleep -Seconds 2
[System.Windows.Forms.SendKeys]::SendWait("tijd")
Start-Sleep -Seconds 1
Save-Screen "4-zoeken"
Stop-Blad $blad

Show-Crash
Write-Host "Smoke test passed."
