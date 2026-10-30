<#
Session du groupe pour RimWorld 1.7 multijoueur : rend la liste de mods, leurs réglages et les versions des mods du
Workshop identiques à ceux de l'hôte (Raysor), pour que Multiplayer ne signale plus de différence en rejoignant.

Lancé par install.ps1 (donc par Installer.bat), RimWorld fermé : télécharge la dernière session publiée par Raysor et
l'applique.
  - Liste de mods : ModsConfig.xml reçoit la liste de Raysor, dans le même ordre.
  - Réglages : ceux que Multiplayer compare (Config\Mod_*.xml des mods actifs, réglages HugsLib). Les réglages
    personnels que Multiplayer ignore (Multiplayer lui-même, caméra, interface...) restent ceux du joueur.
  - Mods du Workshop : ceux qui n'ont pas la même version que chez Raysor sont retéléchargés par Steam (après accord) ;
    ceux qui manquent sont ouverts dans Steam pour s'y abonner.
  Chaque fichier remplacé est d'abord copié dans « Sauvegardes session », dans le dossier de données de RimWorld.

Avec -Publish (Raysor, via PublierSession.bat) : lit sa liste, ses réglages et les versions de ses mods du Workshop et
les publie sur GitHub (release « session » du modpack, jamais « latest »).

Tests : -SessionZip (session locale au lieu de GitHub ; avec -Publish, où l'écrire), -DataPath, -SteamLibraries,
-NoSteam (ne ferme, ne relance ni n'ouvre Steam), -DryRun (montre les changements sans rien modifier), -Yes.
#>
param(
    [switch]$Publish,
    [string]$RimWorldPath = '',
    [string]$DataPath = (Join-Path $env:USERPROFILE 'AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios'),
    [string[]]$SteamLibraries = @(),
    [string]$Repo = 'MrRaysor/RimWorld17-Multijoueur',
    [string]$SessionZip = '',
    [switch]$NoUpload,
    [switch]$NoSteam,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Same list as Multiplayer's SyncConfigs.ignoredConfigsModIds: settings it never compares (personal, screen, UI).
$IgnoredConfigs = @('rwmt.multiplayer', 'hodlhodl.twitchtoolkit', 'dubwise.dubsmintmenus', 'dubwise.dubsmintminimap',
    'arandomkiwi.rimthemes', 'brrainz.cameraplus', 'giantspacehamster.moody', 'fluffy.modmanager', 'jelly.modswitch',
    'betterscenes.rimconnect', 'jaxe.rimhud', 'telefonmast.graphicssettings', 'derekbickley.ltocolonygroupsfinal',
    'dra.multiplayercustomtickrates', 'merthsoft.designatorshapes', 'mlie.usethisinstead', 'm00nl1ght.mappreview')
$HugsLibId = 'unlimitedhugs.hugslib'

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Confirm-Step([string]$Question) {
    if ($Yes) { return $true }
    return (Read-Host "$Question [O/n]") -notmatch '^\s*n'
}

function Get-SteamPath {
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($props.SteamPath) { return ($props.SteamPath -replace '/', '\') }
            if ($props.InstallPath) { return ($props.InstallPath -replace '/', '\') }
        } catch { }
    }
    return $null
}

function Get-SteamLibraries {
    if ($SteamLibraries.Count -gt 0) { return $SteamLibraries }
    $libraries = New-Object System.Collections.Generic.List[string]
    $steam = Get-SteamPath
    if ($steam) {
        $libraries.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $path = $m.Groups[1].Value -replace '\\\\', '\'
                if ($libraries -notcontains $path) { $libraries.Add($path) }
            }
        }
    }
    return $libraries
}

function Find-RimWorld {
    foreach ($lib in Get-SteamLibraries) {
        $dir = 'RimWorld'
        $acf = Join-Path $lib 'steamapps\appmanifest_294100.acf'
        if (Test-Path -LiteralPath $acf) {
            $m = [regex]::Match([IO.File]::ReadAllText($acf), '"installdir"\s+"([^"]+)"')
            if ($m.Success) { $dir = $m.Groups[1].Value }
        }
        $path = Join-Path $lib "steamapps\common\$dir"
        if (Test-Path -LiteralPath (Join-Path $path 'Data\Core\About\About.xml')) { return $path }
    }
    return $null
}

function Test-RimWorldRunning {
    return [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($RimWorldPath, [StringComparison]::OrdinalIgnoreCase) })
}

# The mod's own packageId and name (not those of its dependency lists).
function Read-About([string]$ModFolder) {
    $file = Join-Path $ModFolder 'About\About.xml'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $id = $null
    $name = $null
    try {
        $xml = New-Object Xml.XmlDocument
        $xml.LoadXml([IO.File]::ReadAllText($file))
        foreach ($node in $xml.DocumentElement.ChildNodes) {
            if ($node.LocalName -ieq 'packageId') { $id = $node.InnerText.Trim() }
            elseif ($node.LocalName -ieq 'name') { $name = $node.InnerText.Trim() }
        }
    } catch {
        # RimWorld reads some malformed About.xml anyway: take the packageId outside the dependency lists.
        $text = [regex]::Replace([IO.File]::ReadAllText($file), '(?s)<(modDependencies\w*|loadAfter\w*|loadBefore\w*|incompatibleWith\w*)>.*?</\1>', '')
        $m = [regex]::Match($text, '<packageId>\s*([^<]+?)\s*</packageId>', 'IgnoreCase')
        if ($m.Success) { $id = $m.Groups[1].Value }
    }
    if (-not $id) { return $null }
    if (-not $name) { $name = $id }
    return @{ packageId = $id.ToLowerInvariant(); name = $name }
}

# Steam's record of the Workshop items installed in a library: content version (manifest) and its date.
function Read-WorkshopRecord([string]$Library) {
    $record = @{}
    $acf = Join-Path $Library 'steamapps\workshop\appworkshop_294100.acf'
    if (-not (Test-Path -LiteralPath $acf)) { return $record }
    $installed = [regex]::Match([IO.File]::ReadAllText($acf), '"WorkshopItemsInstalled"\s*\{((?:[^{}]|\{[^{}]*\})*)\}').Groups[1].Value
    foreach ($m in [regex]::Matches($installed, '"(\d+)"\s*\{([^{}]*)\}')) {
        $record[$m.Groups[1].Value] = @{
            manifest = [regex]::Match($m.Groups[2].Value, '"manifest"\s+"(-?\d+)"').Groups[1].Value
            timeupdated = [regex]::Match($m.Groups[2].Value, '"timeupdated"\s+"(\d+)"').Groups[1].Value
        }
    }
    return $record
}

# Mods this PC can load, by packageId: the game's own (Core, DLCs), the Mods folder and the Workshop items of every
# Steam library, with Steam's record of the version installed for each Workshop item.
function Get-Inventory {
    $inv = @{ official = @{}; local = @{}; duplicates = @{}; workshop = @{}; byPackage = @{}; record = @{} }
    foreach ($d in Get-ChildItem -LiteralPath (Join-Path $RimWorldPath 'Data') -Directory -ErrorAction SilentlyContinue) {
        $about = Read-About $d.FullName
        if ($about) { $inv.official[$about.packageId] = @{ folder = $d.Name; name = $about.name } }
    }
    foreach ($d in Get-ChildItem -LiteralPath (Join-Path $RimWorldPath 'Mods') -Directory -ErrorAction SilentlyContinue) {
        $about = Read-About $d.FullName
        if (-not $about) { continue }
        $id = $about.packageId
        if ($inv.local.ContainsKey($id)) {
            if (-not $inv.duplicates.ContainsKey($id)) { $inv.duplicates[$id] = @($inv.local[$id].folder) }
            $inv.duplicates[$id] += $d.Name
        } else {
            $inv.local[$id] = @{ folder = $d.Name; name = $about.name }
        }
    }
    foreach ($lib in Get-SteamLibraries) {
        foreach ($d in Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps\workshop\content\294100') -Directory -ErrorAction SilentlyContinue) {
            if ($inv.workshop.ContainsKey($d.Name)) { continue }
            $about = Read-About $d.FullName
            if (-not $about) { continue }
            $inv.workshop[$d.Name] = @{ packageId = $about.packageId; name = $about.name }
            if (-not $inv.byPackage.ContainsKey($about.packageId)) { $inv.byPackage[$about.packageId] = @() }
            $inv.byPackage[$about.packageId] += $d.Name
        }
        $record = Read-WorkshopRecord $lib
        foreach ($key in $record.Keys) { $inv.record[$key] = $record[$key] }
    }
    return $inv
}

# Content version Steam publishes now for each Workshop item (public API, no key): the manifest of its latest update.
function Get-PublishedManifests([string[]]$Ids) {
    $result = @{}
    for ($i = 0; $i -lt $Ids.Count; $i += 100) {
        $batch = @($Ids[$i..([Math]::Min($i + 99, $Ids.Count - 1))])
        $body = @{ itemcount = $batch.Count }
        for ($j = 0; $j -lt $batch.Count; $j++) { $body["publishedfileids[$j]"] = $batch[$j] }
        try {
            $r = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $body -TimeoutSec 30 -UseBasicParsing
            foreach ($d in $r.response.publishedfiledetails) { if ($d.hcontent_file) { $result[[string]$d.publishedfileid] = [string]$d.hcontent_file } }
        } catch {
            Say "  Steam injoignable : dernières versions non vérifiées ($($_.Exception.Message))." DarkYellow
            break
        }
    }
    return $result
}

# Makes Steam download Workshop items again, in the version it publishes now. With Steam closed, the items leave
# Steam's record of installed items and their folders are deleted (no file of the old version is left behind); Steam
# downloads them again as soon as it starts.
function Update-WorkshopItems([string[]]$Ids) {
    $steam = Get-SteamPath
    $steamExe = $null
    if ($steam) { $steamExe = Join-Path $steam 'steam.exe' }
    if (-not $NoSteam) {
        if (-not $steamExe -or -not (Test-Path -LiteralPath $steamExe)) { Say '  Steam introuvable.' Red; return $false }
        if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
            Say '  Fermeture de Steam...'
            Start-Process -FilePath $steamExe -ArgumentList '-shutdown'
            for ($i = 0; $i -lt 120 -and (Get-Process -Name steam -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
            if (Get-Process -Name steam -ErrorAction SilentlyContinue) { Say '  Steam ne s''est pas fermé : ferme-le, puis relance.' Red; return $false }
        }
    }
    foreach ($lib in Get-SteamLibraries) {
        $acf = Join-Path $lib 'steamapps\workshop\appworkshop_294100.acf'
        if (Test-Path -LiteralPath $acf) {
            $text = [IO.File]::ReadAllText($acf)
            foreach ($id in $Ids) { $text = [regex]::Replace($text, '[ \t]*"' + $id + '"\s*\{[^{}]*\}[ \t]*(\r?\n)?', '') }
            [IO.File]::WriteAllText($acf, $text, (New-Object Text.UTF8Encoding($false)))
        }
        foreach ($id in $Ids) {
            $folder = Join-Path $lib "steamapps\workshop\content\294100\$id"
            if (Test-Path -LiteralPath $folder) { [IO.Directory]::Delete($folder, $true) }
        }
    }
    if ($NoSteam) { return $false }
    Say '  Steam redémarre et retélécharge ces mods (laisse cette fenêtre ouverte)...'
    Start-Process -FilePath $steamExe -ArgumentList '-silent'
    $deadline = (Get-Date).AddMinutes(20)
    $shown = -1
    while ($true) {
        $done = 0
        foreach ($id in $Ids) {
            foreach ($lib in Get-SteamLibraries) {
                if (Test-Path -LiteralPath (Join-Path $lib "steamapps\workshop\content\294100\$id\About\About.xml")) { $done++; break }
            }
        }
        if ($done -ne $shown) { Say "  Steam : $done/$($Ids.Count) mod(s) téléchargé(s)"; $shown = $done }
        if ($done -eq $Ids.Count) { Start-Sleep -Seconds 5; return $true }
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Seconds 5
    }
}

function Read-ActiveMods([string]$File) {
    $block = [regex]::Match([IO.File]::ReadAllText($File), '(?s)<activeMods>(.*?)</activeMods>').Groups[1].Value
    return @([regex]::Matches($block, '<li>\s*([^<]+?)\s*</li>') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
}

# Replaces the active mod list of ModsConfig.xml, keeping the rest of the file and its encoding.
function Write-ActiveMods([string]$File, [string[]]$Ids) {
    $bytes = [IO.File]::ReadAllBytes($File)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($File)
    $nl = "`n"
    if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $block = '<activeMods>' + $nl + (($Ids | ForEach-Object { "    <li>$_</li>" }) -join $nl) + $nl + '  </activeMods>'
    $pattern = New-Object Text.RegularExpressions.Regex('(?s)<activeMods\s*/>|<activeMods>.*?</activeMods>')
    if (-not $pattern.IsMatch($text)) { throw 'ModsConfig.xml sans liste de mods' }
    [IO.File]::WriteAllText($File, $pattern.Replace($text, $block.Replace('$', '$$'), 1), (New-Object Text.UTF8Encoding($bom)))
}

function Test-SameFile([string]$A, [string]$B) {
    return (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
}

# Copies a file of RimWorld's data folder into this run's backup folder before it is replaced or removed.
function Backup-File([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return }
    $target = Join-Path $BackupDir $File.Substring($DataPath.TrimEnd('\').Length + 1)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $File -Destination $target -Force
}

# Runs gh without letting its error output stop the script (Windows PowerShell turns it into errors).
function Invoke-Gh {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $script:GhOutput = & gh @args 2>&1 } finally { $ErrorActionPreference = $previous }
    return $LASTEXITCODE
}

# Where each active mod of the host comes from: game, Mods folder (local) or Workshop, with the Workshop version.
function Build-Session([string[]]$Active) {
    $inv = Get-Inventory
    $mods = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($id in $Active) {
        $bare = $id -replace '_steam$', ''
        if ($inv.official.ContainsKey($bare)) {
            $mods.Add([ordered]@{ packageId = $bare; name = $inv.official[$bare].name; source = 'official'; folder = $inv.official[$bare].folder })
        } elseif ($id -eq $bare -and $inv.local.ContainsKey($bare)) {
            # A local folder takes the packageId; the Workshop copy of the same mod is then "<packageId>_steam".
            $mods.Add([ordered]@{ packageId = $bare; name = $inv.local[$bare].name; source = 'local'; folder = $inv.local[$bare].folder })
            if ($inv.duplicates.ContainsKey($bare)) { $problems.Add("$($inv.local[$bare].name) : plusieurs copies dans Mods ($($inv.duplicates[$bare] -join ', ')), garde-n'en qu'une.") }
        } elseif ($inv.byPackage.ContainsKey($bare)) {
            $ids = @($inv.byPackage[$bare])
            $wid = $ids[0]
            $entry = [ordered]@{ packageId = $bare; name = $inv.workshop[$wid].name; source = 'workshop'; folder = $wid; workshopId = $wid; manifest = ''; timeupdated = '' }
            if ($inv.record.ContainsKey($wid)) { $entry.manifest = $inv.record[$wid].manifest; $entry.timeupdated = $inv.record[$wid].timeupdated }
            $mods.Add($entry)
            if ($ids.Count -gt 1) { $problems.Add("$($entry.name) : plusieurs mods du Workshop ont l'identifiant $bare ($($ids -join ', ')), désabonne-toi de ceux que tu n'utilises pas.") }
        } else {
            $problems.Add("$id : mod actif introuvable sur ce PC.")
        }
    }
    return @{ mods = $mods; problems = $problems }
}

# Workshop mods of the session whose installed version is not the one Steam publishes now.
function Get-StaleMods($Mods) {
    $workshop = @($Mods | Where-Object { $_.source -eq 'workshop' })
    if ($workshop.Count -eq 0) { return @() }
    $published = Get-PublishedManifests @($workshop | ForEach-Object { $_.workshopId })
    return @($workshop | Where-Object { $published.ContainsKey($_.workshopId) -and $published[$_.workshopId] -ne $_.manifest })
}

if (-not $RimWorldPath) { $RimWorldPath = Find-RimWorld }
if (-not $RimWorldPath -or -not (Test-Path -LiteralPath $RimWorldPath)) { Say 'RimWorld introuvable.' Red; return }
$configDir = Join-Path $DataPath 'Config'
$modsConfig = Join-Path $configDir 'ModsConfig.xml'
if (-not (Test-Path -LiteralPath $modsConfig)) { Say "Lance RimWorld une première fois : pas de liste de mods dans $configDir." Red; return }
$BackupDir = Join-Path $DataPath ('Sauvegardes session\' + (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss'))

if ($Publish) {
    Say ''
    Say '=== Publier la session : liste, réglages et versions des mods ===' Cyan
    $active = Read-ActiveMods $modsConfig
    Say "Mods actifs : $($active.Count)"
    $built = Build-Session $active
    $stale = Get-StaleMods $built.mods
    if ($stale.Count -gt 0) {
        Say "$($stale.Count) mod(s) du Workshop ont une mise à jour que Steam n'a pas encore installée chez toi :" Yellow
        foreach ($m in $stale) { Say "  - $($m.name)" Yellow }
        if (-not $NoUpload) {
            if (Test-RimWorldRunning) { Say 'Ferme RimWorld (Steam ne met pas à jour les mods d''un jeu ouvert), puis relance la publication.' Red; return }
            if ($NoSteam -or -not (Confirm-Step 'Les faire retélécharger par Steam maintenant (Steam va redémarrer) ?')) {
                Say 'Publication annulée : tes amis auraient une autre version de ces mods.' Red
                return
            }
            if (-not (Update-WorkshopItems @($stale | ForEach-Object { $_.workshopId }))) { Say 'Steam n''a pas fini : relance la publication quand ses téléchargements sont terminés.' Red; return }
            $built = Build-Session $active
            $stale = Get-StaleMods $built.mods
            if ($stale.Count -gt 0) { Say "Toujours pas à jour : $(($stale | ForEach-Object { $_.name }) -join ', '). Relance plus tard." Red; return }
        }
    }
    if ($built.problems.Count -gt 0) {
        foreach ($p in $built.problems) { Say "  $p" Red }
        if (-not $NoUpload) { Say 'Publication annulée : corrige ces points, puis relance.' Red; return }
    }

    # Settings Multiplayer compares: Config\Mod_<folder>_<class>.xml of each active mod, and HugsLib's file.
    $stage = Join-Path ([IO.Path]::GetTempPath()) 'rw17mp-session-publish'
    if (Test-Path -LiteralPath $stage) { [IO.Directory]::Delete($stage, $true) }
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'Config') | Out-Null
    $files = 0
    foreach ($m in $built.mods) {
        if ($IgnoredConfigs -contains $m.packageId) { continue }
        $m.configs = @()
        foreach ($f in Get-ChildItem -LiteralPath $configDir -File -Filter "Mod_$($m.folder)_*.xml" -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $stage "Config\$($f.Name)")
            $m.configs += $f.Name
            $files++
        }
    }
    $hugsLib = Join-Path $DataPath 'HugsLib\ModSettings.xml'
    $hasHugsLib = (@($built.mods | Where-Object { $_.packageId -eq $HugsLibId }).Count -gt 0) -and (Test-Path -LiteralPath $hugsLib)
    if ($hasHugsLib) { Copy-Item -LiteralPath $hugsLib -Destination (Join-Path $stage 'HugsLib-ModSettings.xml') }
    $session = [ordered]@{
        created = (Get-Date).ToString('dd/MM/yyyy HH:mm')
        gameVersion = [string](Get-Content -LiteralPath (Join-Path $RimWorldPath 'Version.txt') -TotalCount 1 -ErrorAction SilentlyContinue)
        hugsLibSettings = $hasHugsLib
        # ToArray, not @(): Windows PowerShell fails on @() around a list of objects ("argument types do not match").
        mods = $built.mods.ToArray()
    }
    [IO.File]::WriteAllText((Join-Path $stage 'session.json'), ($session | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    $zip = $SessionZip
    if (-not $zip) { $zip = Join-Path ([IO.Path]::GetTempPath()) 'session.zip' }
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
    [IO.Directory]::Delete($stage, $true)
    $extra = ''
    if ($hasHugsLib) { $extra = ' + HugsLib' }
    Say "Session prête : $($built.mods.Count) mods, $files fichier(s) de réglages$extra."
    if ($NoUpload) { Say "Non publiée (-NoUpload) : $zip" Yellow; return }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Say 'GitHub CLI (gh) introuvable : installe-le, puis « gh auth login ».' Red; return }
    if ((Invoke-Gh release view session --repo $Repo) -ne 0) {
        $notes = 'Liste de mods, réglages et versions des mods du Workshop de Raysor, mis à jour avant chaque session. Installer.bat les applique : rien à télécharger ici.'
        if ((Invoke-Gh release create session --repo $Repo --prerelease --title 'Session en cours' --notes $notes) -ne 0) {
            Say "Échec de la création de la release « session » : $script:GhOutput" Red
            return
        }
    }
    if ((Invoke-Gh release upload session $zip --repo $Repo --clobber) -ne 0) { Say "Échec de l'envoi sur GitHub : $script:GhOutput" Red; return }
    Say 'Session publiée : tes amis relancent Installer.bat (RimWorld fermé) et ont la même chose que toi.' Green
    return
}

Say ''
Say '=== Session de Raysor : liste, réglages et versions des mods ===' Cyan
if (-not $DryRun -and (Test-RimWorldRunning)) { Say 'RimWorld est ouvert : ferme-le, puis relance.' Yellow; return }
$work = Join-Path ([IO.Path]::GetTempPath()) 'rw17mp-session'
if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = $SessionZip
    if (-not $zip) {
        $zip = Join-Path $work 'session.zip'
        $web = New-Object Net.WebClient
        $web.Headers['User-Agent'] = 'RimWorld17-Multijoueur-installer'
        try {
            $web.DownloadFile("https://github.com/$Repo/releases/download/session/session.zip", $zip)
        } catch {
            if ($_.Exception.Message -match '404') { Say 'Raysor n''a pas encore publié de session : rien à aligner.' Yellow; return }
            throw
        } finally { $web.Dispose() }
    }
    $unpacked = Join-Path $work 'session'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpacked)
    $session = [IO.File]::ReadAllText((Join-Path $unpacked 'session.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $sessionMods = @($session.mods)
    Say "Session publiée le $($session.created) : $($sessionMods.Count) mods."
    $problems = New-Object System.Collections.Generic.List[string]
    $changes = 0
    $version = [string](Get-Content -LiteralPath (Join-Path $RimWorldPath 'Version.txt') -TotalCount 1 -ErrorAction SilentlyContinue)
    if ($session.gameVersion -and $version -and $version -ne $session.gameVersion) {
        $problems.Add("RimWorld $version ici, $($session.gameVersion) chez Raysor : mettez le jeu à jour dans Steam.")
    }

    # Which mod of this PC is each mod of the session, and is it the same Workshop version.
    $inv = Get-Inventory
    $wanted = New-Object System.Collections.Generic.List[string]
    $folders = @{}
    $missing = New-Object System.Collections.Generic.List[object]
    $different = New-Object System.Collections.Generic.List[object]
    foreach ($m in $sessionMods) {
        $id = [string]$m.packageId
        if ($id -notmatch '^[a-z0-9][a-z0-9._-]*$') { $problems.Add("Identifiant de mod invalide ignoré : $id"); continue }
        if ($m.source -eq 'workshop') {
            $wid = [string]$m.workshopId
            if ($wid -notmatch '^\d+$') { $problems.Add("$($m.name) : numéro Workshop invalide."); continue }
            # A local folder with the same packageId would take Raysor's place: his mod is then the Workshop copy.
            if ($inv.local.ContainsKey($id)) { $wanted.Add($id + '_steam') } else { $wanted.Add($id) }
            if (-not $inv.workshop.ContainsKey($wid)) { $missing.Add($m); continue }
            $folders[$id] = $wid
            $mine = ''
            if ($inv.record.ContainsKey($wid)) { $mine = $inv.record[$wid].manifest }
            if ($m.manifest -and $mine -ne $m.manifest) { $different.Add($m) }
        } elseif ($m.source -eq 'local') {
            $wanted.Add($id)
            if (-not $inv.local.ContainsKey($id)) { $problems.Add("$($m.name) : mod local de Raysor absent du dossier Mods."); continue }
            $folders[$id] = $inv.local[$id].folder
            if ($inv.duplicates.ContainsKey($id)) { $problems.Add("$($m.name) : plusieurs copies dans Mods ($($inv.duplicates[$id] -join ', ')), garde seulement « $($m.folder) ».") }
        } else {
            $wanted.Add($id)
            if (-not $inv.official.ContainsKey($id)) { $problems.Add("$($m.name) : extension absente de ton jeu."); continue }
            $folders[$id] = $inv.official[$id].folder
        }
    }

    if ($missing.Count -gt 0) {
        Say ''
        Say "$($missing.Count) mod(s) du Workshop de la liste de Raysor ne sont pas installés chez toi :" Yellow
        foreach ($m in ($missing | Select-Object -First 20)) { Say "  - $($m.name) : https://steamcommunity.com/sharedfiles/filedetails/?id=$($m.workshopId)" Yellow }
        if ($missing.Count -gt 20) { Say "  ... et $($missing.Count - 20) autres." Yellow }
        if ($missing.Count -gt 5) {
            # Many at once (first install): RimSort reads the list written below and subscribes to all of them.
            $problems.Add("Ouvre RimSort (sans lancer RimWorld) : il propose de télécharger avec Steam les mods manquants de la liste (« Download with Steam client »). Quand Steam a fini, relance Installer.bat.")
        } else {
            $problems.Add("Abonne-toi aux $($missing.Count) mod(s) manquant(s), attends que Steam les télécharge, puis relance Installer.bat.")
            if (-not $NoSteam -and -not $DryRun -and (Confirm-Step 'Ouvrir leurs pages dans Steam pour t''y abonner ?')) {
                foreach ($m in $missing) {
                    Start-Process "steam://url/CommunityFilePage/$($m.workshopId)"
                    Read-Host "  $($m.name) : clique sur « S'abonner » dans Steam, puis appuie sur Entrée" | Out-Null
                }
            }
        }
    }

    if ($different.Count -gt 0) {
        # Older here: Steam gives the version Raysor has. Newer here (it is the one Steam publishes): Raysor is late.
        $published = Get-PublishedManifests @($different | ForEach-Object { [string]$_.workshopId })
        $behind = @($different | Where-Object { -not $inv.record.ContainsKey([string]$_.workshopId) -or $published[[string]$_.workshopId] -ne $inv.record[[string]$_.workshopId].manifest })
        $ahead = @($different | Where-Object { $behind -notcontains $_ })
        if ($behind.Count -gt 0) {
            Say ''
            Say "$($behind.Count) mod(s) du Workshop ne sont pas dans la même version que chez Raysor :" Yellow
            foreach ($m in $behind) { Say "  - $($m.name)" Yellow }
            if ($DryRun) {
                $changes += $behind.Count
            } elseif (Confirm-Step 'Les faire retélécharger par Steam (Steam va redémarrer) ?') {
                try { Update-WorkshopItems @($behind | ForEach-Object { [string]$_.workshopId }) | Out-Null } catch { Say "  Erreur : $($_.Exception.Message)" Red }
                $inv = Get-Inventory
                foreach ($m in $behind) {
                    $wid = [string]$m.workshopId
                    if (-not $inv.workshop.ContainsKey($wid)) { $problems.Add("$($m.name) : pas encore retéléchargé par Steam (relance Installer.bat quand Steam a fini).") }
                    elseif ($inv.record.ContainsKey($wid) -and $inv.record[$wid].manifest -ne $m.manifest) { $ahead += $m }
                }
            } else {
                $problems.Add("$($behind.Count) mod(s) du Workshop dans une autre version que chez Raysor.")
            }
        }
        if ($ahead.Count -gt 0) {
            $problems.Add("Raysor doit mettre à jour ces mods puis republier la session : $(($ahead | ForEach-Object { $_.name }) -join ', ').")
        }
    }

    $current = Read-ActiveMods $modsConfig
    if ((@($current) -join '|') -ne (@($wanted) -join '|')) {
        $changes++
        $added = @($wanted | Where-Object { $current -notcontains $_ }).Count
        $removed = @($current | Where-Object { $wanted -notcontains $_ }).Count
        Say "Liste de mods : alignée sur celle de Raysor ($added ajouté(s), $removed retiré(s), même ordre)."
        if (-not $DryRun) { Backup-File $modsConfig; Write-ActiveMods $modsConfig @($wanted) }
    } else {
        Say 'Liste de mods : déjà identique.'
    }

    # Settings: Raysor's files, named after this PC's folder of each mod; files Raysor does not have are set aside
    # (the mod then uses its default settings, as at Raysor's).
    $settings = 0
    foreach ($m in $sessionMods) {
        $id = [string]$m.packageId
        if ($IgnoredConfigs -contains $id -or -not $folders.ContainsKey($id)) { continue }
        $hostPrefix = "Mod_$($m.folder)_"
        $myPrefix = "Mod_$($folders[$id])_"
        $expected = @{}
        foreach ($name in @($m.configs)) {
            $name = [string]$name
            if (-not $name.StartsWith($hostPrefix) -or $name -notmatch '^Mod_[^\\/:*?"<>|]+\.xml$' -or $name.Contains('..')) { continue }
            $expected[$myPrefix + $name.Substring($hostPrefix.Length)] = Join-Path $unpacked "Config\$name"
        }
        foreach ($name in $expected.Keys) {
            $target = Join-Path $configDir $name
            if ((Test-Path -LiteralPath $target) -and (Test-SameFile $expected[$name] $target)) { continue }
            $settings++
            if (-not $DryRun) { Backup-File $target; Copy-Item -LiteralPath $expected[$name] -Destination $target -Force }
        }
        foreach ($f in Get-ChildItem -LiteralPath $configDir -File -Filter "$myPrefix*.xml" -ErrorAction SilentlyContinue) {
            if ($expected.ContainsKey($f.Name)) { continue }
            $settings++
            if (-not $DryRun) { Backup-File $f.FullName; Remove-Item -LiteralPath $f.FullName }
        }
    }
    if ($session.hugsLibSettings) {
        $source = Join-Path $unpacked 'HugsLib-ModSettings.xml'
        $target = Join-Path $DataPath 'HugsLib\ModSettings.xml'
        if (-not (Test-Path -LiteralPath $target) -or -not (Test-SameFile $source $target)) {
            $settings++
            if (-not $DryRun) {
                Backup-File $target
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Copy-Item -LiteralPath $source -Destination $target -Force
            }
        }
    }
    $changes += $settings
    if ($settings -gt 0) { Say "Réglages : $settings fichier(s) alignés sur ceux de Raysor." } else { Say 'Réglages : déjà identiques.' }
    if (-not $DryRun -and (Test-Path -LiteralPath $BackupDir)) { Say "Anciens fichiers sauvegardés dans : $BackupDir" DarkGray }

    Say ''
    if ($DryRun) { Say "Simulation : $changes changement(s) à faire, rien n'a été modifié." Cyan }
    if ($problems.Count -eq 0) {
        if (-not $DryRun) { Say 'Prêt : même liste de mods, mêmes réglages et mêmes versions que Raysor.' Green }
    } else {
        Say 'Reste à régler avant de jouer :' Yellow
        foreach ($p in $problems) { Say "  - $p" Yellow }
    }
} finally {
    if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
