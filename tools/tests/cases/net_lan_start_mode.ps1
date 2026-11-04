# net_lan_start_mode -- the Host of a LAN lobby switches the game to an online event mode and launches
# it; both instances run ModeManager::StartGameMode into that mode's own Start. The console fills the
# whole GameModeParams there (the online race, road rage and burning home run bodies).
#
# Run it (a PAIR case -- see net_lan_pair.ps1 for how pair cases work):
#   $env:BP_START_MODE = '10'   # 10 race (default), 11 road rage, 13 burning home run
#   powershell -ExecutionPolicy Bypass -File tools\tests\run_pair.ps1 -Case net_lan_start_mode
#
# THE STIMULUS (Host only). BRN_NET_SCRIPT asks for the preset event list (GUI 193, what the online game
# options screen posts on entry). BRN_NET_START_MODE posts GUI 257 GuiEventNetworkGameParams, the record
# that screen posts, one round on the first preset online event with landmarks. Then BRN_NET_SCRIPT
# posts the launch into the network queue (a 'gui' record never reaches the network StateManager): GUI 54 for the race; GUI 56 (force launch) for the two team modes,
# whose teams nobody picks in an unattended lobby, so GUI 54 would answer "not enough teams".
#
# THE ORACLE ([net] mode-start, ModeManager::StartGameMode's [FLAG PC witness], printed right after the
# mode's Start): params-type and params-online are the mode's, and the checkpoint and start-location
# counts are the round's. On a build where the mode has no Start the params are unfilled stack bytes.
param([string]$Role = '')
. (Join-Path $PSScriptRoot '..\_net_pair_common.ps1')

$liMode = if ($env:BP_START_MODE) { [int]$env:BP_START_MODE } else { 10 }
$lsLaunchGui = if ($env:BP_START_LAUNCH_GUI) { $env:BP_START_LAUNCH_GUI } elseif ($liMode -eq 10) { 54 } else { 56 }
$lsModeName = @{ 10 = 'OnlineRace'; 11 = 'OnlineRoadRage'; 13 = 'OnlineBurningHomeRun' }[$liMode]
# OnlineGameOptions::RequestPresetEvents: road rage asks for the race list.
$liPresetType = if ($liMode -eq 13) { 13 } else { 10 }

# GUI 281 (NetworkInLoadingScreenShown) stands in for OnlineLoading's own post: on this build that
# screen waits forever in LOADING_COMPONENTS (see the run report), and StartGameMode waits on it.
$lsLoadedScript = '85:out:281;100:out:281;115:out:281'

# Road rage launches only with exactly two teams (StateManager::GameModeHasEnoughTeams), and nobody
# picks one in an unattended lobby: the Guest posts GUI 265 (switch team) once it has the new mode.
$lsGuestTeam = if ($liMode -eq 11) { '35:net:265;' } else { '' }

$lPairRoles = [ordered]@{
  Host  = @{ Other = 'Guest'; Harness = "BRN_NET_HOST=1,BRN_NET_START_MODE=25:$liMode,BRN_NET_SCRIPT=10:gui:193:$liPresetType;40:net:$lsLaunchGui;50:net:$lsLaunchGui;60:net:$lsLaunchGui;$lsLoadedScript" }
  Guest = @{ Other = 'Host';  Harness = "BRN_NET_JOIN=1,BRN_NET_SCRIPT=$lsGuestTeam$lsLoadedScript" }
}

if ($Role -eq '') {
  return @{
    Name = 'net_lan_start_mode'
    Area = 'network'
    Bug  = "ModeManager::StartGameMode runs $lsModeName's own Start over LAN, with a filled GameModeParams"
    Pair = @{ Roles = @($lPairRoles.Keys); Slots = @(1, 2) }
  }
}
if (-not $lPairRoles.Contains($Role)) { throw "net_lan_start_mode: unknown -Role '$Role' (Host or Guest)" }
$lR = $lPairRoles[$Role]

$lFilled = {
  param($ctx)
  $lsRx = '\[net\] mode-start mode=' + $lsModeName + ' type=(\d+) params-type=(-?\d+) params-online=(\d+) light=([0-9A-F]+)'
  $lLine = @($ctx.LogLines | Where-Object { $_ -match $lsRx }) | Select-Object -First 1
  if ($null -eq $lLine) { return @{ Pass = $false; Detail = "no [net] mode-start line for $lsModeName" } }
  $null = $lLine -match $lsRx
  return @{ Pass = ([int]$Matches[1] -eq $liMode -and [int]$Matches[2] -eq $liMode -and [int]$Matches[3] -eq 1 -and $Matches[4] -ne 'FFFFFFFF'); Detail = $lLine.Trim() }
}.GetNewClosure()

$lCounts = {
  param($ctx)
  $lsRx = '\[net\] mode-start mode=' + $lsModeName + ' checkpoints=(\d+) start-locations=(\d+)'
  $lLine = @($ctx.LogLines | Where-Object { $_ -match $lsRx }) | Select-Object -First 1
  if ($null -eq $lLine) { return @{ Pass = $false; Detail = "no [net] mode-start count line for $lsModeName" } }
  $null = $lLine -match $lsRx
  return @{ Pass = ([int]$Matches[1] -gt 0 -and [int]$Matches[2] -eq 2); Detail = $lLine.Trim() }
}.GetNewClosure()

@{
  Name    = "net_lan_start_mode_$Role"
  Area    = 'network'
  Bug     = "none -- the $Role half of net_lan_start_mode (run it through tools\tests\run_pair.ps1)"
  Frames  = $true
  Run     = @{ MaxSeconds = 230; TitleStart = $true; SkipIntro = $true; AcceptGap = 1.0; FrameEvery = 300 }
  DiagEnv = "$($lR.Harness),BRN_NET_DELAY=20,BRN_SCREEN_DIAG=1"
  Setup   = (& $NetPair.Setup $Role)
  Checks  = @(
    @{ Kind = 'NewAsserts'; Name = 'no NEW assert families' }
    @{ Kind = 'LogCount'; Name = 'no exceptions'; Pattern = '\[EXCEPTION\]'; Max = 0 }
    @{ Kind = 'Mark';     Name = 'reached DRIVING'; Phase = 'DRIVING' }
    @{ Kind = 'Script';   Name = "$lsModeName's Start filled the params"; Script = $lFilled }
    @{ Kind = 'Script';   Name = 'round checkpoints and a start location per car'; Script = $lCounts }
  )
}
