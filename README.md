# ECFA Theme

An ITGmania theme for [ECFA Cloud](https://ecfa.online), the ECFA score tracker, with Waterfall judging (as played
in ECFA 2021).

Only for ITGmania. Source: <https://github.com/lohmcodes/ECFATheme>

## Setup

Clone or download this repository into ITGmania's `Themes` folder (e.g. `Themes/ECFATheme`) and select it as the
theme in ITGmania's options.

ITGmania only lets themes talk to hosts listed in `HttpAllowHosts` in `Save/Preferences.ini` (a comma-separated
list). ECFA Cloud is the only one the theme needs: scores, every leaderboard (GrooveStats and ArrowCloud EX
included) and theme updates all go through it.

```ini
HttpAllowHosts=<existing hosts>,ecfa.online
```

If the host is blocked, the title menu shows a message saying which host to add.

To point the theme at a different server (for example a local development server), create `Save/ECFACloud.ini`:

```ini
[ECFACloud]
ServerURL=http://localhost:3000
```

That host must also be in `HttpAllowHosts`.

## Waterfall judging

Waterfall is the only play mode.

- **Timing windows**: Masterful 15 ms, Awesome 30 ms, Solid 50 ms, OK 100 ms, Fault 160 ms (holds 300 ms,
  mines 71.5 ms, rolls 350 ms). Weights 10 / 9 / 6 / 3 / 0 / 0 (miss), held 6, mine −3. The engine judges
  with these (`SL.Preferences.Waterfall` / `SL.Metrics.Waterfall` in `Scripts/SL_Init.lua`), so its
  percent score *is* the Waterfall score.
- **Lifebars** (`Scripts/WF-LifeBars.lua`): Easy, Normal and Hard run at the same time. Failing Easy fails
  the song (play continues); the hardest lifebar left at the end decides the clear. The
  `Lifebar` player option picks which one is shown. The engine's own lifebar never moves.
- **Clear types**: Mastery (all Masterful), Awesome Combo, Solid Combo, Full Combo (no Faults, Misses, mine
  hits or dropped holds), then Hard Clear, Clear, Easy Clear.
- **FA+**: Masterfuls within 12.5 ms (10 ms with the smaller split) are counted and can be shown split in the
  judgment font, step statistics and error bars.
- **Secondary ITG/EX score** (`Scripts/WF-Scoring.lua`): every tap's offset is re-judged with ITG's windows
  (with Decents off: hits in the Decent range count as Way Offs) and run through a simulated ITG lifebar. That feeds everything that used to show EX (EX score display,
  Hard EX, evaluation Pane 2, rival pace). Hits outside Waterfall's 160 ms Fault window are already misses,
  so ITG's widest window (181.5 ms) is approximate.
- Local high scores are saved to the profile's `Waterfall-Stats.xml`.
- Judgment fonts show Waterfall's judgments (Masterful ... Miss).

## What ECFA Cloud adds

- **Login.** After profile select, players without an API key see a QR code (`ScreenECFACloudLogin`). Scanning
  it and approving the link on ecfa.online hands this machine an API key, which is saved to the profile's
  `ECFACloud.ini`. The QR code only carries a hash of a secret that never leaves the machine, so someone watching
  the screen (e.g. on a stream) can't collect the key. The operator option `QRLogin` controls when the screen
  appears.
- **Leaderboards.** The song select scorebox (or the bottom pane, per the `MusicWheelGS` theme option), the
  sort menu's leaderboard popup and the gameplay scorebox show EX and Waterfall (WF) boards only, each labeled
  with which it is and where the scores come from: Blended EX (first), GrooveStats EX, ArrowCloud EX, ECFA Cloud
  WF, and the event's WF leaderboard when the chart is part of an open ECFA Cloud event. The `Show Score Boxes`
  player option picks which ones the scoreboxes rotate through.
- **Blended leaderboard.** The popup's first page, and "Blended EX" in the `Show Score Boxes` player option,
  list the chart's EX scores from ECFA Cloud, GrooveStats and ArrowCloud together in one list, best first, each
  row tagged EC, GS or AC. ECFA Cloud fetches the other two (`external=1` on `player-leaderboards`), so players
  need no keys or accounts there, and nothing is ever submitted to them. A score another service already listed
  for the same player (names compared ignoring case, spaces and punctuation, or differing by a last initial) is
  shown once. GrooveStats scores need `GROOVESTATS_API_KEY` on the ECFA Cloud server; when a service is
  unavailable, the popup's legend dims it. The code is in `Scripts/SL-Helpers-BlendedLeaderboard.lua`.

## Theme updates

When GitHub has a newer version of the theme, the title menu lists **Update Theme**. It compares every installed
file with the new version's, downloads only the ones that differ (each checked against its SHA-256), copies them in
once all of them have arrived, and reloads the theme. Nothing changes if a download fails or Back is pressed first.

- Every push to `master` runs `.github/workflows/update-manifest.yml`, which force-pushes `version.json` and
  `manifest.json` (every file's SHA-256) to the `update-manifest` branch. The theme reads them, and the files,
  through ECFA Cloud (`/api/v1/theme/`), so no other host needs allowing.
- Each published commit gets a version: `ThemeInfo.ini`'s major.minor and the number of commits (e.g. 1.0.42).
  The title screen shows it once the updater has installed that commit (or, in a git clone, once the startup
  check sees the clone is on it). Bump the major or minor in `ThemeInfo.ini` for a bigger release.
- The installed version is `Other/installed-version.txt` (written by the updater), or the commit of a git clone.
- ITGmania can't delete files from Lua, so files removed from the theme stay behind. Removed `Scripts/` and
  `Modules/` files are emptied so they no longer run.
- In a theme folder that's a git clone, updating in game leaves the files ahead of git. Use
  `git fetch && git reset --hard origin/master` before going back to `git pull`.
- The code is in `Scripts/SL-Helpers-ThemeUpdate.lua` and `BGAnimations/ScreenECFAThemeUpdate underlay/`.
- **Score submission.** Passed Waterfall plays are submitted automatically on the evaluation screen
  (`ScreenEvaluation common/Shared/AutoSubmitScore.lua`): Waterfall judgments, lifebars, FA+ counts, the
  simulated ITG judgments and the timing windows in use, along with pack, song and chart details, and song
  banners the server is missing. Personal bests and world records are announced on screen.
- **Offline queue.** If a score can't be submitted (the machine is offline, or ECFA Cloud is unreachable), it's
  saved to the profile's `ECFACloudPending.jsonl` (up to 50 plays) and uploaded after the next successful
  submission, with its real play time (`Scripts/SL-ECFACloud-Pending.lua`).
- **Events.** When the server has events turned on, evaluation pane 9 shows event results (points, rank,
  progress) for charts in an open event.

The integration lives in `Scripts/SL-Helpers-ECFACloud.lua`. The API it uses is documented in the ECFA Cloud
repository (`docs/API.md`).

### Hard EX Score

A local-only scoring display (not submitted to ECFA Cloud), computed from the simulated ITG judgments:
`PerPlayer/ScoreHardEx.lua`, plus marquee behavior in the Evaluation screen's `JudgmentLabels.lua`/`JudgmentNumbers.lua`
that alternates between the EX score and a pink "H.EX" (Hard EX) score when both `ShowExScore` and
`ShowHardEXScore` player options are enabled.

## Also included

Scorebox and Step Statistics, per-foot/per-arrow scatter plots, configurable theme fonts, ghost data,
Routine/Couples mode, NoteSkin variants, and more. See `Modules/README.md` for how isolated screen hooks plug in
without editing core theme files.
