# Copies the mod into the Transport Fever 3 user mods folder (Steam app 3493540).
# Overwrites files in place; delete the installed folder by hand if you rename or remove files.
$src = Join-Path $PSScriptRoot "luke_line_tracker_1"
$mods = Get-ChildItem "C:\Program Files (x86)\Steam\userdata\*\3493540\local\mods" -Directory | Select-Object -First 1
if (-not $mods) { throw "TF3 user mods folder not found" }
Copy-Item $src $mods.FullName -Recurse -Force
Write-Output ("Installed to " + (Join-Path $mods.FullName "luke_line_tracker_1"))
