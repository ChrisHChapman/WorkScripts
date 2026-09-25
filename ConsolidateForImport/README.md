# ConsolidateForImport

Gathers all files around a target folder into that folder, moves it up one level, and renames it `<part1>_<part2>_FOR_IMPORT`.

## Usage

Keep `ConsolidateForImport.bat` and `ConsolidateForImport.ps1` in the same folder, then either:

- **Drag** the target folder onto `ConsolidateForImport.bat`, or
- **Double-click** `ConsolidateForImport.bat` and pick the target folder. The picker opens at `Z:\DICOM_TEMP\HDR Images for MIM` (if that drive is mapped); to change this, edit `$StartFolder` near the top of the `.ps1`.

## What it does

Given `...\Grandparent\Parent\ABC_12345_Whatever` as the target:

1. Moves every file from the other folders in `Parent` (including subfolders, hidden files) and any loose files in `Parent` into the target. `Thumbs.db` and `desktop.ini` are not moved; they are deleted along with the folders that contain them.
2. Deletes those emptied folders.
3. Moves the target to `...\Grandparent\ABC_12345_FOR_IMPORT`.
4. Deletes `Parent` after verifying it is empty.

Before changing anything it checks for, and stops on:

- target name with fewer than two underscores
- `ABC_12345_FOR_IMPORT` already existing in `Grandparent`
- duplicate file names (among incoming files or against files already in the target)

It then shows a summary and asks `Proceed? (Y/N)`.

## Notes

- If a file is locked (e.g., open in another program) the script stops at that point; completed moves are not undone.
- If Windows says the script is blocked, right-click the `.ps1` → Properties → check **Unblock**. If your organization's policy forbids running PowerShell scripts entirely, the `.bat` launcher cannot override that.
