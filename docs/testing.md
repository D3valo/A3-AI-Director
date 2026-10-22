# Testing

Three levels, from cheapest to the real thing.

| Level | Run | Covers |
| --- | --- | --- |
| Unit tests | `cargo test` in `extension\`; `.venv\Scripts\python -m unittest discover -s tests -t .` in `companion\` | Extension commands and callbacks, the catalogue's checks, pacing, requests, personalities, campaign reports |
| End to end, no Arma | `companion\.venv\Scripts\python -I tools\e2e_test.py [--backend claude-code]` (also part of `tools\build.ps1`, offline) | The built DLL through Arma's own entry points, against a running companion: a state in, a decision out through the callback, an error when the companion is down |
| In game | `!director test` in chat | Everything that needs Arma and Antistasi (below) |

## In-game test session

Use a throwaway Antistasi save: the test spends and grants real resources and starts real missions.

1. Build if the extension changed: `tools\build.ps1`.
2. Start the companion in its own window, with a test campaign so the reports stay out of the real one:

   ```powershell
   cd companion
   .venv\Scripts\python -m director --campaign test serve
   ```

3. Start Arma with the group's mod list and the dev build of the director: `hemtt launch infinizo` (see
   [hosting.md](hosting.md)), or `hemtt launch antistasi` for Antistasi alone. Host a local game and load the save.
4. In chat:

   | Type | Expect |
   | --- | --- |
   | `!director status` | A reply only you see: on, propose mode, every 90 s, style, soldiers alive |
   | `!director test` | About a minute of `[Director test]` lines and a summary. The director pauses meanwhile |
   | `!director send a patrol at me` | `Request sent`, then within seconds a `[Director] Proposes ...` line |
   | `!approve` | The proposal runs |
   | `!director style merciless`, then `!director status` | The style changes |
   | `!director test full` | Also launches an Antistasi offensive: last, and only on the throwaway save |

   The self-test checks: the extension, the game state, a round trip to the companion and Claude, narrate, a test
   patrol from the occupiers' templates (deleted afterwards), the soldier cap, intel markers, the weather, and in
   Antistasi a small donation, a new mission and a support call. WARN means Antistasi chose not to act (no
   suitable mission site, no affordable support), which is normal; FAIL means something is broken.
5. Play for a while, then Ctrl+C in the companion window and let it write the report.

Afterwards, `companion\.venv\Scripts\python -I tools\rpt_lines.py` prints the director's lines from the latest
`.rpt` (`--tests` for the self-test only), including any script errors in its functions. The decisions and
reports are in `companion\campaigns\test\`.
