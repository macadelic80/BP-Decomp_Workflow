# superjump_failed -- crashing during a first super-jump attempt shows "JumpFailed" (b5-decomp#80).
#
# THE CHAIN. StuntManager::UpdateJumps arms mbIsAttemptingJumpForFirstTime on take-off when the
# profile has not done the jump. StuntManager::Update latches mbNeedToSendJumpFailureMessage when
# the player crashes with that flag armed, and posts action 265 on the first frame the player is
# no longer crashing. TranslateGameActionsToGuiEvents turns 265 into GuiEventSuperJumpFailed
# (GUI 549), HudMessageAnalyzer case 549 triggers "JumpFailed", and the director posts it (154)
# to the HUD state that is live that frame -- FBurnMainHudState, re-entered as the crash ends.
#
# THE BUG this case measures: FBurnMainHudState::Update climbed SETUP -> LOADING -> WFINIT ->
# RUNNING one phase per frame and cleared its in-queue every frame, so the 154 posted on the
# crash-exit frame was thrown away before RUNNING ever saw it. The console (0x82481A10) falls
# through every ready phase in the same frame.
#
# THE SCENARIO. flow_run's -Jump preset launches the car at 50 m/s from z=-330 along the axis of
# jump region 4030 (box centre (3028.7, -1.2, -250.9), 6 m wide, one-way +Z) -- no throttle is
# needed. The shot fires at physics frame ~2730, take-off arms at ~2860, the car lands at ~2900
# and the jump would count 0.5 s later, so BRN_CRASH_PLAYER=2905 crashes it on the landing,
# before it completes. FreshProfile keeps the jump undone (firstTime=1).
#
# A crash while the "SuperJump" name banner is still transitioning in (crash frame ~2880, run
# timing permitting) also covers the companion fix: CrashedHudState re-starts that banner in
# crashHudMessages_mc, which has no "SuperJump" frame, and the label miss used to fault in
# MovieClipInstance::ApplyKeyFrame. InGameMessagesComponent::StartMessage now retires it, so
# the "no exceptions" check holds there too.
#
# Run it:
#   powershell -ExecutionPolicy Bypass -File tools\tests\run_case.ps1 -Case superjump_failed
#
@{
  Name    = 'superjump_failed'
  Area    = 'ui'
  Bug     = 'b5-decomp#80: the Super Jump Failed message does not show after crashing on a first attempt'
  Frames  = $false
  FreshProfile = $true
  Run     = @{
    Drive       = $true
    MotionProbe = $true
    MaxSeconds  = 160
    SkipIntro   = $true
    AcceptGap   = 1.0
    Jump        = $true                      # flow_run's launch preset, one shot
    CrashSweep  = '3029.0,-9.2,-330.0'       # on the axis of jump region 4030 at (3028.7, -250.9), +Z
    JumpSpeeds  = '50'
    CrashPlayer = 2905                       # physics frame: on the landing, before the jump counts
  }
  # BRN_FREEROAM_DIAG arms `[freeroam-gui] action A -> gui G`; BRN_HUDMSG_DIAG arms the
  # `[hudmsg]` analyzer/director trace. The `[jump-ladder]` take-off rung is unconditional.
  DiagEnv = 'BRN_FREEROAM_DIAG=1,BRN_HUDMSG_DIAG=1'
  Checks  = @(
    @{ Kind = 'NewAsserts'; Name = 'no NEW assert families' }
    @{ Kind = 'LogCount';   Name = 'no exceptions';   Pattern = '\[EXCEPTION\]'; Max = 0 }
    @{ Kind = 'Mark';       Name = 'reached DRIVING'; Phase = 'DRIVING' }

    # The precondition: a first-time take-off.
    @{ Kind = 'LogMatch';   Name = 'the super jump took off'
       Pattern = '\[jump-ladder\] action=56 OnJumpStart posted .*firstTime=1' }

    # The producer and the bridge arm, and the message reaching the director's queue.
    @{ Kind = 'LogMatch';   Name = 'action 265 translated to GUI 549'
       Pattern = '\[freeroam-gui\] action 265 -> gui 549 ' }
    @{ Kind = 'Script'; Name = 'JumpFailed queued by the HUD message director'; Script = {
        param($ctx)
        $lines = $ctx.LogLines
        for ($i = 0; $i -lt $lines.Count; $i++) {
          if ($lines[$i] -match '\[hudmsg\] director: filter "JumpFailed"') {
            for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 6); $j++) {
              if ($lines[$j] -match '\[hudmsg\] director:   queued') {
                return @{ Pass = $true; Detail = "JumpFailed queued at log line $j" }
              }
              if ($lines[$j] -match '\[hudmsg\] director:   dropped: (.*)') {
                return @{ Pass = $false; Detail = "JumpFailed dropped at log line ${j}: $($Matches[1])" }
              }
            }
          }
        }
        return @{ Pass = $false; Detail = 'no [hudmsg] director filter line for JumpFailed' }
    } }

    # THE ARM: the live HUD state took the message and started it.
    @{ Kind = 'LogMatch';   Name = 'the HUD message component started JumpFailed'
       Pattern = 'HUD MSGS : STARTING MESSAGE NAMED "JUMPFAILED' }
  )
}
