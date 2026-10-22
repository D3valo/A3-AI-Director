# AI Director

A server-side game master for Arma 3, driven by Claude. Every 90 seconds the server sends a summary of the game
state to a companion program running on the same PC. The companion asks Claude for one decision (wait, narrate,
send a patrol, or have Antistasi call in support), checks it against an allow-list and a cooldown budget, and the
mod carries it out.

| Action | Effect | Cooldown |
| --- | --- | --- |
| `wait` | Nothing (the usual answer) | - |
| `narrate` | A line of atmosphere shown to all players as a hint | 2 min |
| `spawn_patrol` | A fireteam or squad hunting a player, from out of sight 600-1000 m away | 10 min |
| `call_support` | Antistasi only: the occupiers react as if they had spotted a player and radioed for help; Antistasi's own support logic sends a QRF, artillery, air support or nothing, paid from their defence resources | 15 min |
| `offer_mission` | Antistasi only: a new rebel task through Antistasi's mission request (assassination, conquest, destroy, logistics, supplies, rescue, convoy); not a type already active | 20 min |
| `launch_offensive` | Antistasi only: a major attack chosen by Antistasi (`A3A_fnc_chooseAttack`), possibly on the HQ; needs 400+ attack resources and no big attack in progress | 60 min |
| `reveal_enemies` | Enemy groups within 1.5 km of a player marked on every map for 5 minutes | 10 min |
| `reward_rebels` | Antistasi only: small (300 money, 1 recruit) or large (1000 money, 3 recruits) donation | 30 min |
| `change_weather` | Clear, overcast, rain, storm or fog, over 5 minutes | 20 min |
| `vehicle_patrol` | Antistasi only: an armed light vehicle with a fireteam drives in from a road 0.9-1.5 km away and hunts near a player | 15 min |
| `roadblock` | Antistasi only: an armed vehicle and a fireteam hold a road 500-900 m ahead of a player's direction of travel | 20 min |
| `heli_recon` | Antistasi only: a light helicopter circles a player for two minutes without firing; nearby enemy groups learn where the players are | 15 min |
| `sniper_team` | Antistasi only: a sniper and spotter on high ground 400-800 m away with a view of a player | 15 min |
| `informant` | A civilian walks up to a player; when reached, says the director's line and marks nearby enemies on the map | 20 min |
| `supply_drop` | Antistasi only: a captured enemy crate with Antistasi loot parachutes in 100-200 m away, marked and with green smoke | 30 min |
| `enemy_vip` | Antistasi only: an officer and escort patrol 0.7-1.2 km away, marked for 10 minutes; killing him pays the rebels 500 | 30 min |

Encounters are built from the enemy side's Antistasi templates for the war level, spawned out of players' sight, set
up with Antistasi's own unit and vehicle functions, paid for from its attack resources, and despawned by Antistasi
once no rebels are near. Those that spawn soldiers count against `AID_maxDirectorUnits`.

**Which enemy.** Claude chooses, per hostile action, whether the occupiers or the invaders (Antistasi's second enemy)
carry it out, spending that side's resources and never a defeated side. The default is the occupiers, or
`AID_patrolSide` if set.

**Rebel HQ.** `AID_protectHQ` (also `!director hq`) keeps attacks off the HQ:

| Setting | Effect |
| --- | --- |
| `director` (default) | The director's offensives never pick the HQ, and its hostile encounters never target a player within `AID_hqRadius` (500 m) of it |
| `all` | As `director`, and Antistasi's own attacks on the HQ are stopped too: Antistasi only targets the HQ once an enemy's HQ knowledge reaches 1, and the director holds it just below |
| `off` | No protection |

The actions are defined once in `companion/director/catalogue.py` (`ACTIONS`: fields, cooldown, Antistasi-only);
the prompt in `prompt.py` tells Claude when each fits.

Proof of concept. The design, its reasoning, status and roadmap are in [docs/plan.md](docs/plan.md).

```
Arma 3 server                       Companion (Python, same PC)              Claude API
addons/main (SQF)                   companion/director
  gatherState -> toJSON
  callExtension send_state  ---->   POST 127.0.0.1:47800/decide
  (extension/, Rust, arma-rs)         ask Claude (structured output)  ---->  Opus 5.5 via claude -p or the API
                                      check allow-list + cooldowns    <----
  ExtensionCallback         <----     JSON decision, logged
  dispatch: narrate / spawnPatrol / callSupport
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
| `companion` | Python companion: `director/` package, `samples/state.json`, `tests/`; `campaigns/` (not in git) holds each campaign's logs, reports and story |
| `tools/build.ps1` | Tests and builds the extension, copies the DLL into the mod root, runs the end-to-end test, runs `hemtt build` |
| `tools/install.cmd`, `tools/start-session.cmd` (and their `.ps1` scripts) | Install the built mod for real sessions; start a session (companion window + Arma with the group's mods); the `.cmd` launchers work from any terminal or a double-click ([docs/hosting.md](docs/hosting.md)) |
| `tools/e2e_test.py`, `tools/rpt_lines.py` | End-to-end test without Arma; the director's lines from the latest `.rpt` ([docs/testing.md](docs/testing.md)) |

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

For real sessions with the group, `tools\install.cmd` once and then `tools\start-session.cmd` each session do all of
this; see [docs/hosting.md](docs/hosting.md), which also covers a dedicated server. By hand, for development:

1. Start the companion (keep the window open):

   ```powershell
   cd companion
   .venv\Scripts\python -m director --campaign infinizo serve   # options below
   ```

   One decision for a saved state, without the game: `.venv\Scripts\python -m director decide samples\state.json`.
2. Start Arma with the mod: `hemtt launch` (CBA only), `hemtt launch antistasi`, or `hemtt launch infinizo` (the group's mods), with BattlEye off. On a
   dedicated server, load the built mod with `-serverMod=`; clients don't need it.
3. Host a mission. The server's `.rpt` shows `[AI Director] Extension 0.1.0 loaded.` and then one line per
   decision.
4. After the session, press Ctrl+C in the companion window and let it finish: Claude writes the session's
   after-action report and updates the campaign's story so far, which the director reads next session. If the
   window was closed instead, run `.venv\Scripts\python -m director --campaign infinizo report` afterwards.

## Companion options

Options before the command apply to all commands; `--max-skip` and `--no-report` go after `serve`.

| Option | Default | Effect |
| --- | --- | --- |
| `--campaign <name>` | `default` | Which campaign's logs, reports and story to use |
| `--personality <style>` | the campaign's, else `balanced` | `balanced`, `cinematic` (atmosphere and set pieces), `merciless` (more pressure, little help), `supportive` (small fights, more help), or a custom style (below). `serve` remembers it for the campaign; `!director style` overrides it for the session |
| `--personalities <file>` | `companion\personalities.toml` | Custom styles |
| `--backend <name>` | `claude-code` | `claude-code`, `api` or `offline` |
| `--effort <level>` | `low` | `low`, `medium` or `high` thinking for decisions |
| `serve --max-skip <s>` | `300` | While nothing important changes (no deaths, big damage, change in nearby enemies, movement of a few hundred metres, mission or war-level change, time of day), wait without asking Claude, for up to this many seconds. `0` asks every time. Saves usage in quiet spells and long fights |
| `serve --no-report` | off | Don't write the report and story on Ctrl+C |

Skipped decisions are logged as waits with the backend `skipped`.

### Custom styles

Copy `companion\personalities.example.toml` to `companion\personalities.toml` and edit it. Each `[name]` with a
`style = "..."` text adds a style (or replaces a built-in one of the same name); the text is added to the director's
instructions for the whole session. The example has `grimdark` and `guerrilla`. The after-action report names the
style the session ran with and any change during it.

## Campaigns

Each campaign (`--campaign <name>`, default `default`) keeps its own memory in `companion\campaigns\<name>\`, so
separate games don't mix:

| Path | What |
| --- | --- |
| `logs\decisions-*.jsonl` | Every decision of a session with the state, Claude's reason and token usage |
| `reports\decisions-*.md` | After-action report for each session, written for the players |
| `story.md` | The story so far, rewritten after each session; the director reads it as background for continuity. Edit it freely, or delete it to start the campaign's story afresh |
| `arc.json` | The story arc in progress, if any |
| `campaign.json` | Settings that stick to the campaign: its style (`{"personality": "cinematic"}`), saved by `serve --personality` |

## Chat commands

Type these in any chat channel. They are hidden from everyone's chat, and only the host, logged-in or voted admins,
and players whose Steam UID is in `AID_chatUIDs` can use them; replies go to the sender only.

| Command | Effect |
| --- | --- |
| `!director <what you want>` | Ask the director for something, e.g. `!director give us a convoy to ambush` (sets `AID_request`) |
| `!approve` / `!deny` | Run or drop the proposed decision |
| `!director status` | On or off, mode, interval, and whether a proposal is waiting |
| `!director on` / `!director off` | Turn the director on or off |
| `!director auto` / `!director propose` | Run decisions at once, or wait for `!approve` |
| `!director style <name>` | Change the director's style for this session: a built-in or custom style, or `default` (the campaign's own). If the companion doesn't know the name, it says so and keeps the campaign's. `!director style` shows the current one |
| `!director hq off` / `director` / `all` | HQ protection (see Rebel HQ above); `!director hq` shows it |
| `!director arc <idea>` / `arc` / `arc status` / `arc stop` | Start a story arc from your idea (or the director's own), show the running one, or stop it ([Story arcs](#story-arcs)) |
| `!director test` / `!director test full` | Run the in-game self-test against yourself ([docs/testing.md](docs/testing.md)); `full` also launches an offensive, so only on a throwaway save |
| `!director help` | List the commands |

Players don't need the mod: the server sends the chat hook to every client, including players who join later.

## Controls (debug console, server exec)

| Command | Effect |
| --- | --- |
| `AID_enabled = false` | Off switch: stop sending states and ignore decisions |
| `AID_chatUIDs = ["7656119..."]` | Extra players allowed to use the chat commands |
| `AID_maxDirectorUnits = 24` | The most director-spawned soldiers alive at once; further patrols are refused (default 24) |
| `AID_protectHQ = "all"`, `AID_hqRadius = 500` | HQ protection (above) and the radius that counts as at the HQ |
| `AID_mode = "auto"` | Run decisions at once (default `"propose"`: announced in chat, wait for approval) |
| `[] call AID_fnc_approve` | Run the proposed decision |
| `AID_request = "send a patrol at us"` | Ask the director for something in plain words. Sent at once; the companion keeps it until a decision carries it out (cooldowns still apply) or Claude says it can't be done with the available actions |
| `AID_interval = 60` | Seconds between states |
| `AID_patrolSide = Invaders` | Side for hostile actions when Claude doesn't choose one (default: Antistasi's `Occupants`, or `east` outside Antistasi) |
| `AID_patrolUnits` | Unit classes for patrols outside Antistasi (default: vanilla CSAT riflemen) |

In Antistasi, patrols come from the side's faction template at the current war level (a 5-man fireteam or an 8-man
squad), are spawned and initialised with Antistasi's own functions, cost 10 attack resources per soldier, and
despawn once no rebels are near.

To force an action without asking Claude: `["<player name>", "squad"] spawn AID_fnc_spawnPatrol` or
`createHashMapFromArray [["action", "narrate"], ["message", "..."]] call AID_fnc_dispatch` (both server exec).

## Next steps

See [docs/plan.md](docs/plan.md): the in-game test session first.

## What the director hears back

Each state carries what happened since the last one, so the director can learn from its own moves:

| Feedback | Examples |
| --- | --- |
| Outcomes of its actions | `Your spawn_patrol (occupants) against Alpha 1-1, 6 min ago: wiped out, all 5 killed, contact after 2 min`; what Antistasi actually sent for `call_support` (or that it sent nothing); no mission created for `offer_mission`; offensive launched or not; informant reached; supply crate landed; the VIP killed or got away |
| Encounters under way | Each director encounter still alive: soldiers alive, minutes since contact |
| Events | Kill tallies by side, players down or back up, players killed, locations taken (with their Antistasi names), big attacks starting and ending, missions starting and ending, the host approving, denying or ignoring proposals |
| Where the players are | Each player's nearest named location, who holds it and how far, distance to the HQ, vehicle |

Events other than kill tallies make the director ask Claude even in a quiet spell; tallies from skipped states are
passed on with the next one. The after-action report uses them to say what happened, not only what was sent.

## Story arcs

`!director arc the occupiers hunt the cell that ambushed their convoy` (or just `!director arc`) has Claude plan a
short plot from the idea, the game state and the campaign story: a title, a premise, 3-5 beats with suggested actions
and earliest minutes, and an ending. For the next 20-40 minutes every decision sees the arc and steers towards its
current beat, through the normal actions, cooldowns and limits; a decision that delivers a beat moves it on. Only the
player who started it hears the arc's news (begins, complete, stopped), so the plot isn't spoiled for the others.
`!director arc status` shows the beat; `!director arc stop` ends it; a new arc replaces the running one. The running
arc is saved in `campaigns\<name>\arc.json`, so it survives a companion restart, and the after-action report covers
it. While an arc runs, the director asks Claude every time instead of skipping quiet moments.

## Prompt caching

With the `api` backend, the system prompt (rules, style and the campaign's story, about 2k tokens, all fixed for a
session) carries a 1-hour cache breakpoint, so after the first decision each one reads it from the cache at a tenth
of the input price; the log's `usage.cache_read_input_tokens` shows it. The `claude-code` backend leaves caching to
Claude Code.
