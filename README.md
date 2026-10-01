# ECFA Theme

An ITGmania theme for [ECFA Cloud](https://ecfa.online), the ECFA score tracker. This is a fork of a fork:
[Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) →
[Zmod](https://github.com/zarzob/Simply-Love-SM5) (Zarzob/Zankoku's quality-of-life fork of Simply Love) →
**ECFA Theme** (this repo), which replaces Zmod's GrooveStats integration with ECFA Cloud and its ITG
timing and lifebar with [Waterfall](https://twitter.com/SteveReen/status/1392057636518973442)'s (via Waterfall
Expanded by SteveReen and Zarzob, the theme ECFA 2021 was played on).

Only for ITGmania.

## Setup

ITGmania only lets themes talk to hosts listed in `HttpAllowHosts` in `Save/Preferences.ini`. Add ECFA Cloud:

```ini
HttpAllowHosts=*.ecfa.online,ecfa.online
```

If the host is blocked, the title menu shows a message saying which host to add.

To point the theme at a different server (for example a local development server), create `Save/ECFACloud.ini`:

```ini
[ECFACloud]
ServerURL=http://localhost:3000
```

That host must also be in `HttpAllowHosts`.

## Waterfall judging

The play modes are **Waterfall** and Casual (the old ITG and FA+ modes are gone; profiles that still say
"ITG" play Waterfall).

- **Timing windows**: Masterful 15 ms, Awesome 30 ms, Solid 50 ms, OK 100 ms, Fault 160 ms (holds 300 ms,
  mines 71.5 ms, rolls 350 ms). Weights 10 / 9 / 6 / 3 / 0 / 0 (miss), held 6, mine −3. The engine judges
  with these (`SL.Preferences.Waterfall` / `SL.Metrics.Waterfall` in `Scripts/SL_Init.lua`), so its
  percent score *is* the Waterfall score.
- **Lifebars** (`Scripts/WF-LifeBars.lua`): Easy, Normal and Hard run at the same time. Failing Easy fails
  the song (play continues, as in Waterfall); the hardest lifebar left at the end decides the clear. The
  `Lifebar` player option picks which one is shown. The engine's own lifebar never moves.
- **Clear types**: Mastery (all Masterful), Awesome Combo, Solid Combo, Full Combo (no Faults, Misses, mine
  hits or dropped holds), then Hard Clear, Clear, Easy Clear.
- **FA+**: Masterfuls within 12.5 ms (10 ms with the smaller split) are counted and can be shown split in the
  judgment font, step statistics and error bars.
- **Secondary ITG/EX score** (`Scripts/WF-Scoring.lua`): every tap's offset is re-judged with ITG's windows
  and run through a simulated ITG lifebar. That feeds everything that used to show EX (EX score display,
  Hard EX, evaluation Pane 2, rival pace). Hits outside Waterfall's 160 ms Fault window are already misses,
  so ITG's widest window (181.5 ms) is approximate.
- Local high scores are saved to `Waterfall-Stats.xml`, separate from ITG-judged scores in `Stats.xml`.
- Judgment fonts are Waterfall's (Masterful ... Miss).

## What ECFA Cloud adds

- **Login.** After profile select, players without an API key see a QR code (`ScreenECFACloudLogin`). Scanning
  it and approving the link on ecfa.online hands this machine an API key, which is saved to the profile's
  `ECFACloud.ini`. The QR code only carries a hash of a secret that never leaves the machine, so someone watching
  the screen (e.g. on a stream) can't collect the key. The operator option `QRLogin` controls when the screen
  appears.
- **Leaderboards.** The song select scorebox (or the bottom pane, per the `MusicWheelGS` theme option), the
  sort menu's leaderboard popup and the gameplay scorebox show the chart's ECFA Cloud Waterfall leaderboard and
  the secondary EX (and, in the popup, ITG) leaderboards, plus the event leaderboard when the chart is part of an
  open ECFA Cloud event.
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

## Inherited from Zmod / Simply Love

This fork carries forward Zmod's quality-of-life feature set on top of mainline Simply Love: scorebox and Step
Statistics, Hard/held-miss judgment support, per-foot/per-arrow scatterplots, configurable theme fonts, ghost data,
Routine/Couples mode, NoteSkin Variants, and more. See `Modules/README.md` for how isolated screen hooks plug in
without editing core theme files.

# Credits

Waterfall by SteveReen; Waterfall Expanded (lifebars, judgment fonts, scoring) by SteveReen and Zarzob.

Zmod (the base this fork builds on) is worked on by Zarzob and Zankoku. Contact them on Discord at `zarzob` or
`zankoku`, or via [Zarzob's Discord server](https://discord.gg/zarzob).

## Additional Contributors

  * sorae
  * MegaSphere
  * @florczakraf
  * @HURG-IIDX
