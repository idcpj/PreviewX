Write-Host "PreviewX PowerShell sample"
$items = Get-ChildItem
foreach ($item in $items) {
    Write-Output $item.Name
}