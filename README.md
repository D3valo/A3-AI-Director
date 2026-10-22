# AI Director

A server-side game master for Arma 3, driven by Claude. Every 90 seconds the server sends a summary of the game
state to a companion program running on the same PC. The companion asks Claude for one decision (wait, narrate,
or send a patrol), checks it against an allow-list and a cooldown budget, and the mod carries it out.

Proof of concept. The plan and its reasoning are in the A3UE-Warhammer-40k repo, `docs/plans/ai-zeus.md`.

```
Arma 3 server                       Companion (Python, same PC)              Claude API
addons/main (SQF)                   companion/director
  gatherState -> toJSON
  callExtension send_state  ---->   POST 127.0.0.1:47800/decide
  (extension/, Rust, arma-rs)         ask Claude (structured output)  ---->  Opus 5.5 via claude -p or the API
                                      check allow-list + cooldowns    <----
  ExtensionCallback         <----     JSON decision, logged
  dispatch: narrate / spawnPatrol
```

- **Claude never writes code that runs in the game.** It picks one of the actions in
  `companion/director/catalogue.py`; the companion checks fields and cooldowns, and `fn_dispatch.sqf` only knows
  those actions. `companion/director/backends.py` holds the ways of asking Claude.
- **The game never waits on the companion.** `send_state` returns at once and the reply arrives through the
  `ExtensionCallback` event handler. If the companion is down, the server logs an error and plays on.
- **The extension only talks to loopback** (`set_url` refuses anything else and it is built without TLS). The API
  key lives only in the companion's environment.

## Layout

| Path | What |
| --- | --- |
| `addons/main` | SQF: state gathering, the callback handler, the actions, the off switch |
| `extension` | Rust `cdylib` built on [arma-rs](https://github.com/BrettMayson/arma-rs); becomes `ai_director_x64.dll` |
| `companion` | Python companion: `director/` package, `samples/state.json`, `tests/` |
| `tools/build.ps1` | Tests and builds the extension, copies the DLL into the mod root, runs `hemtt build` |

## Requirements

- Rust (stable, `x86_64-pc-windows-msvc`) with Visual Studio's MSVC build tools
- HEMTT (`hemtt`)
- Python 3.13
- Arma 3 2.20 or later (native `toJSON` / `fromJSON`)
- One of the companion backends:
  - `claude-code` (default): Claude Code installed and logged in with your Claude subscription (`claude auth
    status`). It runs `claude -p` with no tools and none of your CLAUDE.md, hooks or plugins, and counts against
    your plan's usage limits. **For your own games only:** Anthropic's terms don't allow serving other people's
    requests through a Claude subscription, so use `api` for anything shared or public.
  - `api`: an Anthropic API key from the Claude Console (billed per token).
  - `offline`: always waits; tests the plumbing without Claude.

## Setup

```powershell
cd companion
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
```

## Build and test

```powershell
tools\build.ps1                                            # extension tests + DLL + PBO in .hemttout\build
cd companion; .venv\Scripts\python -m unittest discover -s tests -t .
```

## Run

1. Start the companion (keep the window open):

   ```powershell
   cd companion
   .venv\Scripts\python -m director serve                  # --backend claude-code|api|offline, --effort low|medium|high
   ```

   One decision for a saved state, without the game: `.venv\Scripts\python -m director decide samples\state.json`.
2. Start Arma with the mod: `hemtt launch` (CBA only) or `hemtt launch antistasi`, with BattlEye off. On a
   dedicated server, load the built mod with `-serverMod=`; clients don't need it.
3. Host a mission. The server's `.rpt` shows `[AI Director] Extension 0.1.0 loaded.` and then one line per
   decision. Decisions with their reasons and token usage are also in `companion\logs\decisions-*.jsonl`.

## Controls (debug console, server exec)

| Command | Effect |
| --- | --- |
| `AID_enabled = false` | Off switch: stop sending states and ignore decisions |
| `AID_mode = "auto"` | Run decisions at once (default `"propose"`: announced in chat, wait for approval) |
| `[] call AID_fnc_approve` | Run the proposed decision |
| `AID_request = "send a patrol at us"` | Ask the director for something in plain words. Sent at once; the companion keeps it until a decision carries it out (cooldowns still apply) or Claude says it can't be done with the available actions |
| `AID_interval = 60` | Seconds between states |
| `AID_patrolSide = Invaders` | Side for patrols (default: Antistasi's `Occupants`, or `east` outside Antistasi) |
| `AID_patrolUnits` | Unit classes for patrols outside Antistasi (default: vanilla CSAT riflemen) |

In Antistasi, patrols come from the side's faction template at the current war level (a 5-man fireteam or an 8-man
squad), are spawned and initialised with Antistasi's own functions, cost 10 attack resources per soldier, and
despawn once no rebels are near.

To force an action without asking Claude: `["<player name>", "squad"] spawn AID_fnc_spawnPatrol` or
`createHashMapFromArray [["action", "narrate"], ["message", "..."]] call AID_fnc_dispatch` (both server exec).

## Next steps

- Check `AID_request` and Antistasi-template patrols in game.
- More actions through Antistasi's support system (QRFs, mortar fire, convoys), within the same allow-list.
- A larger, cached system prompt (event catalogue, factions, map zones); the current one is below the minimum
  cacheable size for the `api` backend, so `cache_read_input_tokens` stays 0 there until it grows.
