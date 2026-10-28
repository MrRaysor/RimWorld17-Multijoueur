@echo off
title Mods du groupe - RimWorld 1.7 multijoueur
rem Downloads the latest install.ps1 of the modpack and runs it (installs or updates the group's local mods).
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; $w = New-Object Net.WebClient; $w.Encoding = [Text.Encoding]::UTF8; $w.Headers['User-Agent'] = 'RimWorld17-Multijoueur-installer'; $s = $w.DownloadString('https://raw.githubusercontent.com/MrRaysor/RimWorld17-Multijoueur/main/install.ps1').TrimStart([char]0xFEFF); & ([scriptblock]::Create($s))"
if errorlevel 1 echo Erreur pendant l'installation : verifie ta connexion internet et relance ce fichier.
echo.
pause
