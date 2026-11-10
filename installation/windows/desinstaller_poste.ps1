<#
  SSSU-SAJ VMS - désinstallation (lancée par le désinstallateur).
  Arrête et retire le service PostgreSQL et les règles de pare-feu.
  Les DONNÉES (%ProgramData%\SSSU-SAJ VMS : base, photos, clés, sauvegardes)
  sont CONSERVÉES, sauf si -EffacerDonnees est indiqué.
#>
param([switch]$EffacerDonnees)
$ErrorActionPreference = 'Continue'
$service = 'SSSU-SAJ-PostgreSQL'
if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
  Stop-Service -Name $service -Force
  & sc.exe delete $service | Out-Null
}
Get-NetFirewallRule -DisplayName 'SSSU-SAJ VMS*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
if ($EffacerDonnees) {
  Remove-Item -Recurse -Force (Join-Path $env:ProgramData 'SSSU-SAJ VMS')
}
exit 0
