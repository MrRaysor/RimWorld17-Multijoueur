<#
Installe ou met à jour les mods locaux du groupe pour RimWorld 1.7 multijoueur (les mods absents du Steam Workshop),
puis applique la session de Raysor (session.ps1) : sa liste de mods, ses réglages de mods et ses versions des mods du
Workshop. Lancé par Installer.bat (double-clic) ; le relancer avant chaque session, RimWorld fermé.

Il trouve RimWorld via Steam, télécharge la dernière version du modpack sur GitHub et remplace chaque mod dans le dossier
Mods du jeu. Il ne touche pas aux autres mods, ni aux sauvegardes, ni aux dossiers de développement (dossier lié, ou qui
contient Source ou .git).
Tests : -SessionScript (session.ps1 local au lieu de GitHub) et -SessionArgs (ses paramètres de test).
#>
param(
    [string]$RimWorldPath = '',
    [string]$BaseUrl = 'https://github.com/MrRaysor/RimWorld17-Multijoueur/releases/latest/download',
    [switch]$DetectOnly,
    [string]$SessionScript = '',
    [hashtable]$SessionArgs = @{}
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Workshop copies of mods this modpack replaces (same packageId): RimWorld uses the local ones.
$WorkshopCopies = @{ '2606448745' = 'Multiplayer'; '1629973374' = 'Multiplayer Compatibility'; '3014915404' = 'Vehicle Framework' }

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Get-SteamLibraries {
    $steam = $null
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($props.SteamPath) { $steam = $props.SteamPath; break }
            if ($props.InstallPath) { $steam = $props.InstallPath; break }
        } catch { }
    }
    $libraries = New-Object System.Collections.Generic.List[string]
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libraries.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $path = $m.Groups[1].Value -replace '\\\\', '\'
                if (-not $libraries.Contains($path)) { $libraries.Add($path) }
            }
        }
    }
    return $libraries
}

function Test-RimWorldFolder([string]$Path) {
    return [bool]$Path -and (Test-Path -LiteralPath (Join-Path $Path 'Data\Core\About\About.xml'))
}

function Find-RimWorld {
    foreach ($lib in Get-SteamLibraries) {
        $dir = 'RimWorld'
        $acf = Join-Path $lib 'steamapps\appmanifest_294100.acf'
        if (Test-Path -LiteralPath $acf) {
            $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"installdir"\s+"([^"]+)"')
            if ($m.Success) { $dir = $m.Groups[1].Value }
        }
        $path = Join-Path $lib "steamapps\common\$dir"
        if (Test-RimWorldFolder $path) { return $path }
    }
    $default = Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\RimWorld'
    if (Test-RimWorldFolder $default) { return $default }

    Say 'RimWorld introuvable automatiquement : choisis son dossier dans la fenêtre qui s''ouvre.' Yellow
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Dossier d''installation de RimWorld (celui qui contient le dossier Data)'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-RimWorldFolder $dialog.SelectedPath)) {
        return $dialog.SelectedPath
    }
    return $null
}

# Version installed by this script for each mod folder (sha256 of the archive), to skip mods already up to date.
function Read-State([string]$File) {
    $state = @{}
    if (Test-Path -LiteralPath $File) {
        try {
            $json = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) { $state[$p.Name] = [string]$p.Value }
        } catch { }
    }
    return $state
}

# A folder this script must never replace: a link to a project, or a folder with sources (a mod being developed).
function Test-DevelopmentFolder($Item) {
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $true }
    return (Test-Path -LiteralPath (Join-Path $Item.FullName 'Source')) -or (Test-Path -LiteralPath (Join-Path $Item.FullName '.git'))
}

Say ''
Say '=== Mods du groupe pour RimWorld 1.7 multijoueur ===' Cyan

$rw = $RimWorldPath
if (-not $rw) { $rw = Find-RimWorld }
if (-not $rw -or -not (Test-Path -LiteralPath $rw)) {
    Say 'RimWorld introuvable : installation annulée.' Red
    return
}
Say "RimWorld : $rw"
if ($DetectOnly) { return }

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($rw, [StringComparison]::OrdinalIgnoreCase) }
if ($running) {
    Say 'RimWorld est ouvert : ferme-le, puis relance cet installateur.' Yellow
    return
}

$mods = Join-Path $rw 'Mods'
New-Item -ItemType Directory -Force -Path $mods | Out-Null
# Downloads and extraction next to the mods (same disk: the new folders are moved in place, not copied).
$work = Join-Path $mods '.rw17mp-temp'
if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
New-Item -ItemType Directory -Path $work | Out-Null
$stateFile = Join-Path $mods '.rw17mp-installed.json'
$state = Read-State $stateFile
$web = New-Object Net.WebClient
$web.Headers['User-Agent'] = 'RimWorld17-Multijoueur-installer'
$failed = 0
try {
    $manifestFile = Join-Path $work 'manifest.json'
    $web.DownloadFile("$BaseUrl/manifest.json", $manifestFile)
    $manifest = [IO.File]::ReadAllText($manifestFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Say "Version du modpack : $($manifest.version)"
    Say ''
    foreach ($mod in $manifest.mods) {
        $target = Join-Path $mods $mod.folder
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($existing -and (Test-DevelopmentFolder $existing)) {
            Say "  $($mod.name) : dossier de développement, laissé tel quel." Yellow
            continue
        }
        if ($existing -and $state[$mod.folder] -eq $mod.sha256) {
            Say "  $($mod.name) : déjà à jour."
            continue
        }
        try {
            Say "  $($mod.name) : téléchargement ($([math]::Round($mod.size / 1MB, 1)) Mo)..."
            $zip = Join-Path $work $mod.asset
            $web.DownloadFile("$BaseUrl/$($mod.asset)", $zip)
            $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $mod.sha256) { throw 'fichier téléchargé incomplet ou modifié' }
            $unpacked = Join-Path $work ($mod.asset + '.d')
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpacked)
            $fresh = Join-Path $unpacked $mod.folder
            if (-not (Test-Path -LiteralPath (Join-Path $fresh 'About\About.xml'))) { throw 'archive inattendue' }
            # Directory.Delete removes links inside the folder without following them.
            if ($existing) { [IO.Directory]::Delete($target, $true) }
            Move-Item -LiteralPath $fresh -Destination $target
            $state[$mod.folder] = $mod.sha256
            Say "  $($mod.name) : installé." Green
        } catch {
            $failed++
            Say "  $($mod.name) : échec ($($_.Exception.Message))." Red
        }
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
} catch {
    $failed++
    Say "Erreur : $($_.Exception.Message)" Red
} finally {
    $web.Dispose()
    if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}

foreach ($id in $WorkshopCopies.Keys) {
    foreach ($lib in Get-SteamLibraries) {
        if (Test-Path -LiteralPath (Join-Path $lib "steamapps\workshop\content\294100\$id")) {
            Say "Note : tu es abonné au mod « $($WorkshopCopies[$id]) » du Workshop. Pas grave, RimWorld utilise la version installée ici ; tu peux t'en désabonner dans Steam." DarkYellow
            break
        }
    }
}

Say ''
if ($failed -gt 0) {
    Say "Il y a eu $failed problème(s) : vérifie ta connexion et relance l'installateur." Red
    return
}
Say 'Les mods du groupe sont installés.' Green

# Then Raysor's session: his mod list, mod settings and Workshop versions (session.ps1, next to this script).
try {
    if ($SessionScript) {
        $code = [IO.File]::ReadAllText($SessionScript, [Text.Encoding]::UTF8)
    } else {
        $client = New-Object Net.WebClient
        $client.Encoding = [Text.Encoding]::UTF8
        $client.Headers['User-Agent'] = 'RimWorld17-Multijoueur-installer'
        try { $code = $client.DownloadString('https://raw.githubusercontent.com/MrRaysor/RimWorld17-Multijoueur/main/session.ps1') } finally { $client.Dispose() }
    }
    & ([scriptblock]::Create($code.TrimStart([char]0xFEFF))) -RimWorldPath $rw @SessionArgs
} catch {
    Say "La session de Raysor n'a pas pu être appliquée : $($_.Exception.Message)" Red
}
