<#
.SYNOPSIS
    Consolidates files into a target folder and prepares it for import.

.DESCRIPTION
    Given a target folder:
      1. Moves every file from the other folders beside it (including their
         subfolders) and any loose files in the parent folder into the target.
      2. Deletes the emptied sibling folders.
      3. Moves the target up one level and renames it, keeping everything up to
         and including the second underscore and appending "FOR_IMPORT"
         (e.g. ABC_12345_Scan_2026 -> ABC_12345_FOR_IMPORT).
      4. Deletes the original parent folder once it is verified empty.

    Thumbs.db and desktop.ini files are not moved; they are deleted with the
    folders that contain them.

    All error conditions are checked before anything is changed, and a summary
    is shown for confirmation.

.PARAMETER TargetPath
    The target folder. If omitted, a folder picker is shown.
#>
param(
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'
$Suffix = 'FOR_IMPORT'
# Windows-generated files that are not moved; they are deleted along with
# the folders that contain them. (-contains is case-insensitive.)
$IgnoredNames = @('Thumbs.db', 'desktop.ini')

function Fail([string]$Message) {
    Write-Host ''
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Host 'No changes were made.' -ForegroundColor Red
    exit 1
}

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

# --- Choose target folder ----------------------------------------------------

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the TARGET folder'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host 'No folder selected. Exiting.'
        exit 0
    }
    $TargetPath = $dialog.SelectedPath
}

$TargetPath = $TargetPath.Trim().Trim('"').TrimEnd('\', '/')

# --- Pre-flight checks (nothing is changed here) -------------------------------

if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
    Fail "Target folder not found: $TargetPath"
}

$target = Get-Item -LiteralPath $TargetPath -Force
$parent = $target.Parent
if ($null -eq $parent -or $null -eq $parent.Parent) {
    Fail "Target must be at least two levels below a drive root so it can be moved up one level: $($target.FullName)"
}
$grandparent = $parent.Parent

# Rename rule: keep through the second underscore, then append the suffix.
$first = $target.Name.IndexOf('_')
$second = if ($first -ge 0) { $target.Name.IndexOf('_', $first + 1) } else { -1 }
if ($second -lt 0) {
    Fail "Target folder name has fewer than two underscores: $($target.Name)"
}
$newName = $target.Name.Substring(0, $second + 1) + $Suffix
$destination = Join-Path $grandparent.FullName $newName

if (Test-Path -LiteralPath $destination) {
    Fail "A file or folder named '$newName' already exists in $($grandparent.FullName)"
}

# Gather what will move.
$siblingDirs = @(Get-ChildItem -LiteralPath $parent.FullName -Directory -Force |
    Where-Object { $_.FullName -ne $target.FullName })
$looseFiles = @(Get-ChildItem -LiteralPath $parent.FullName -File -Force |
    Where-Object { $IgnoredNames -notcontains $_.Name })

$ignoredCount = @(Get-ChildItem -LiteralPath $parent.FullName -File -Force |
    Where-Object { $IgnoredNames -contains $_.Name }).Count
$filesToMove = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($f in $looseFiles) { $filesToMove.Add($f) }
foreach ($d in $siblingDirs) {
    foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force)) {
        if ($IgnoredNames -contains $f.Name) { $ignoredCount++ } else { $filesToMove.Add($f) }
    }
}

# Name clashes: among incoming files, and against what's already in the target.
# Windows file names are case-insensitive.
$seen = @{}
foreach ($item in @(Get-ChildItem -LiteralPath $target.FullName -Force)) {
    $seen[$item.Name.ToLowerInvariant()] = $item.FullName
}
$clashes = New-Object System.Collections.Generic.List[string]
foreach ($f in $filesToMove) {
    $key = $f.Name.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
        $clashes.Add("  $($f.Name)`n      $($seen[$key])`n      $($f.FullName)")
    } else {
        $seen[$key] = $f.FullName
    }
}
if ($clashes.Count -gt 0) {
    Write-Host ''
    Write-Host "Duplicate file names found ($($clashes.Count)):" -ForegroundColor Red
    $clashes | ForEach-Object { Write-Host $_ }
    Fail 'Resolve the duplicate file names above and run again.'
}

# --- Summary and confirmation -----------------------------------------------

$totalBytes = [long]0
foreach ($f in $filesToMove) { $totalBytes += $f.Length }

Write-Host ''
Write-Host 'All checks passed. Planned changes:' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Target folder : $($target.FullName)"
Write-Host "  Parent folder : $($parent.FullName)"
Write-Host ''
Write-Host "  Move $($filesToMove.Count) file(s) ($(Format-Size $totalBytes)) into the target:"
if ($looseFiles.Count -gt 0) {
    Write-Host ("    {0,6}  loose file(s) in parent folder" -f $looseFiles.Count)
}
foreach ($d in $siblingDirs) {
    $n = @($filesToMove | Where-Object { $_.FullName.StartsWith($d.FullName + [IO.Path]::DirectorySeparatorChar) }).Count
    Write-Host ("    {0,6}  from {1}" -f $n, $d.Name)
}
Write-Host ''
Write-Host "  Delete $($siblingDirs.Count) emptied folder(s) listed above."
if ($ignoredCount -gt 0) {
    Write-Host "  Delete $ignoredCount Thumbs.db / desktop.ini file(s) along with those folders (not moved)."
}
Write-Host "  Move and rename target to : $destination"
Write-Host "  Delete parent folder      : $($parent.FullName)  (only if empty)"
Write-Host ''

$answer = Read-Host 'Proceed? (Y/N)'
if ($answer -notmatch '^\s*[Yy]') {
    Write-Host 'Cancelled. No changes were made.'
    exit 0
}

# --- Execute -----------------------------------------------------------------

# Make sure this process isn't holding the parent folder open.
Set-Location -LiteralPath $grandparent.FullName

$step = 'moving files'
try {
    $i = 0
    foreach ($f in $filesToMove) {
        $i++
        Write-Progress -Activity 'Moving files' -Status "$i of $($filesToMove.Count): $($f.Name)" `
            -PercentComplete ([int](100 * $i / [Math]::Max(1, $filesToMove.Count)))
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $target.FullName $f.Name)
    }
    Write-Progress -Activity 'Moving files' -Completed
    Write-Host "Moved $($filesToMove.Count) file(s)."

    $step = 'deleting emptied folders'
    foreach ($d in $siblingDirs) {
        $left = @(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force |
            Where-Object { $IgnoredNames -notcontains $_.Name })
        if ($left.Count -gt 0) {
            throw "Folder still contains $($left.Count) file(s) after moving: $($d.FullName)"
        }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force
    }
    Write-Host "Deleted $($siblingDirs.Count) emptied folder(s)."

    $step = 'moving and renaming the target folder'
    Move-Item -LiteralPath $target.FullName -Destination $destination
    Write-Host "Target is now: $destination"

    $step = 'deleting the parent folder'
    $remaining = @(Get-ChildItem -LiteralPath $parent.FullName -Force |
        Where-Object { $_.PSIsContainer -or $IgnoredNames -notcontains $_.Name })
    if ($remaining.Count -gt 0) {
        Write-Host ''
        Write-Host "WARNING: Parent folder is not empty, so it was NOT deleted: $($parent.FullName)" -ForegroundColor Yellow
        $remaining | ForEach-Object { Write-Host "  $($_.Name)" }
        exit 1
    }
    Remove-Item -LiteralPath $parent.FullName -Recurse -Force
    Write-Host "Deleted parent folder: $($parent.FullName)"
}
catch {
    Write-Progress -Activity 'Moving files' -Completed
    Write-Host ''
    Write-Host "ERROR while $step`: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'The operation stopped partway. Steps completed before this point were not undone.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
exit 0
