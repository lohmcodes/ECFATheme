# ECFA Theme

An ITGmania theme for [ECFA Cloud](https://ecfa.online), the ECFA score tracker. This is a fork of a fork:
[Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) →
[Zmod](https://github.com/zarzob/Simply-Love-SM5) (Zarzob/Zankoku's quality-of-life fork of Simply Love) →
**ECFA Theme** (this repo), which replaces Zmod's GrooveStats integration with ECFA Cloud.

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

## What ECFA Cloud adds

- **Login.** After profile select, players without an API key see a QR code (`ScreenECFACloudLogin`). Scanning
  it and approving the link on ecfa.online hands this machine an API key, which is saved to the profile's
  `ECFACloud.ini`. The QR code only carries a hash of a secret that never leaves the machine, so someone watching
  the screen (e.g. on a stream) can't collect the key. The operator option `QRLogin` controls when the screen
  appears.
- **Leaderboards.** The song select scorebox (or the bottom pane, per the `MusicWheelGS` theme option), the
  sort menu's leaderboard popup and the gameplay scorebox show the chart's ECFA Cloud ITG and EX leaderboards, plus
  the event leaderboard when the chart is part of an open ECFA Cloud event.
- **Score submission.** Scores are submitted automatically on the evaluation screen
  (`ScreenEvaluation common/Shared/AutoSubmitScore.lua`) along with pack, song and chart details, and song banners
  the server is missing. Personal bests and world records are announced on screen.
- **Offline queue.** If a score can't be submitted (the machine is offline, or ECFA Cloud is unreachable), it's
  saved to the profile's `ECFACloudPending.jsonl` (up to 50 plays) and uploaded after the next successful
  submission, with its real play time (`Scripts/SL-ECFACloud-Pending.lua`).
- **Events.** When the server has events turned on, evaluation pane 9 shows event results (points, rank,
  progress) for charts in an open event.

The integration lives in `Scripts/SL-Helpers-ECFACloud.lua`. The API it uses is documented in the ECFA Cloud
repository (`docs/API.md`).

### Hard EX Score

A local-only scoring display (not submitted to ECFA Cloud): `PerPlayer/ScoreHardEx.lua`, plus marquee behavior in
the Evaluation screen's `JudgmentLabels.lua`/`JudgmentNumbers.lua` that alternates between the normal ITG/EX score
and a pink "H.EX" (Hard EX) score when both `ShowExScore` and `ShowHardEXScore` player options are enabled.

## Inherited from Zmod / Simply Love

This fork carries forward Zmod's quality-of-life feature set on top of mainline Simply Love: scorebox and Step
Statistics, Hard/held-miss judgment support, per-foot/per-arrow scatterplots, configurable theme fonts, ghost data,
Routine/Couples mode, NoteSkin Variants, and more. See `Modules/README.md` for how isolated screen hooks plug in
without editing core theme files.

# Credits

Zmod (the base this fork builds on) is worked on by Zarzob and Zankoku. Contact them on Discord at `zarzob` or
`zankoku`, or via [Zarzob's Discord server](https://discord.gg/zarzob).

## Additional Contributors

  * sorae
  * MegaSphere
  * @florczakraf
  * @HURG-IIDX
