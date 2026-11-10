# Exécute un script PowerShell. En cas d'échec, publie les lignes d'erreur et la
# fin du journal comme annotations GitHub.
param([Parameter(Mandatory = $true)][string]$Script, [string[]]$Arguments = @())
$journal = Join-Path $env:RUNNER_TEMP 'journal.txt'
$code = 0
try {
  & $Script @Arguments *>&1 | Tee-Object -FilePath $journal
  if ($LASTEXITCODE) { $code = $LASTEXITCODE }
} catch {
  $_ | Out-String | Add-Content $journal
  $code = 1
}
function Encoder([string]$t) { ($t -replace '%', '%25' -replace "`r", '' -replace "`n", '%0A') }
if ($code -ne 0) {
  $lignes = Get-Content $journal
  $err = ($lignes | Select-String -Pattern 'error|exception|failed|échec|cannot|not found' | Select-Object -First 40 | ForEach-Object { $_.Line }) -join "`n"
  if ($err) { Write-Host "::error title=Erreurs ($Script)::$(Encoder $err)" }
  Write-Host "::error title=Fin du journal ($Script)::$(Encoder (($lignes | Select-Object -Last 40) -join "`n"))"
}
exit $code
