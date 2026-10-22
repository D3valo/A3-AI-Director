# Plan: AI Director

Claude as a game master for cooperative Arma 3 sessions, built for Antistasi Ultimate. It works in two modes:

1. **Campaign author (between sessions):** writes side missions, events and compositions as files with Claude
   Code, and reads `.rpt` logs and saves to plan the next session. This needs no new software.
2. **Live director (during play):** watches the game state and every minute or two decides whether something
   should happen: atmosphere, a patrol, a support call, a mission, an offensive. The mod carries the decision out.

This repo is the live director. It started as a plan in the A3UE-Warhammer-40k repo (2026-10-21) and became a
working proof of concept on 2026-10-22. The README covers setup and use; this document records the design, the
reasoning behind it, where it stands and what comes next.

## Architecture

```
Arma 3 server (or host)                Companion (Python, same PC)                 Claude
-----------------------                ---------------------------                 ------
addons/main (SQF, server only)
  every 90 s, or at once for a
  host request: gather state, toJSON
  callExtension send_state  ------->   POST 127.0.0.1:47800/decide
  (extension/: Rust, arma-rs;            prompt: rules + catalogue (fixed)
   returns at once, posts from a         + story so far + recent decisions
   background thread)                    + pending request + state   ------->     Opus 5.5, via `claude -p`
                                         structured decision           <-------     (subscription) or the API
                                         checks: allow-list, fields,
                                         preconditions, cooldowns
  ExtensionCallback  <-------------      JSON decision, logged
  propose (chat, !approve) or auto
  dispatch -> Antistasi's own functions
```

On Ctrl+C the companion has Claude turn the session's log into an after-action report and an updated story so
far, which the director reads next session.

### Design decisions

| Decision | Why |
| --- | --- |
| Claude chooses from a fixed set of actions, never writes code | Nothing Claude says can run arbitrary SQF. Each action is defined once (`ACTIONS` in `catalogue.py`), checked by the companion, and `fn_dispatch.sqf` only knows those actions |
| Structured output for every decision | A JSON schema (`output_config.format` on the API, `--json-schema` for `claude -p`) guarantees the shape; forced tool choice isn't available on current models |
| Limits enforced in code, not the prompt | Required fields, game-state preconditions (Antistasi present, mission type not already active, no offensive during a big attack or without 400 attack resources) and per-action cooldowns |
| Rust with arma-rs for the extension | The established Arma extension framework: callbacks, value conversion and a test harness that runs without Arma |
| `ExtensionCallback` instead of polling | `callExtension` must return at once; the decision is pushed to SQF when it arrives |
| Loopback HTTP between extension and companion | Simple to test with `curl`; `set_url` refuses anything but loopback and the extension is built without TLS, so the game process never talks to the internet |
| A separate companion process | Holds the credentials, can be stopped or restarted without touching the game, and is easy to iterate on in Python |
| Fresh short request per decision | Cost and latency stay flat over a long session; continuity comes from the last five decisions and the story so far |
| Antistasi's own functions for every action | Patrols come from the faction templates for the war level and cost attack resources; support goes through `A3A_fnc_requestSupport` with its resource and safety checks; missions, attacks and rebel resources through Antistasi's mission request, attack choice and `resourcesFIA`. The director stays inside Antistasi's economy and balance |
| Server-only mod | Clients need nothing. The chat hook is sent to clients as code (Antistasi allows all remote execution) |
| Propose mode by default | The host approves each action in chat while the director is being tuned; `auto` runs them at once |
| Campaign memory as a written story | A short story so far, rewritten after each session, gives continuity at a fixed small cost, and players can read or edit it |

### Backends

| Backend | Pays with | Notes |
| --- | --- | --- |
| `claude-code` (default) | The host's Claude subscription, through `claude -p` | Runs with `--safe-mode`, no tools, an empty working folder and no API key in its environment. Allowed for personal use of your own subscription; not for serving other people's requests, so a shared or public server should use `api`. Counts against the plan's usage limits. Measured: about 4 s, 2k input and 200 output tokens per decision |
| `api` | An Anthropic API key (Claude Console) | Prompt caching and server-side refusal fallbacks (`fallbacks: "default"`). Estimated about $0.05 per decision at Opus 5.5 prices, so $1.50-3 an hour at one decision every 1-2 minutes; measure from the logged usage |
| `offline` | Nothing | Always waits; tests the plumbing |

Managed Agents and the Agent SDK were considered and rejected: each decision is a single quick structured answer
about the local game, not a long-running agent with a workspace.

## Safety and fairness

- Allow-listed actions only, checked by both the companion and the SQF dispatcher. Unknown actions or bad fields
  become a logged `wait`.
- Cooldowns per action, and every action spends the enemy's own Antistasi resources where Antistasi has them.
- Off switch: `!director off` in chat or `AID_enabled = false`.
- Chat commands only from the host, admins and `AID_chatUIDs`.
- Credentials never enter the game, the mod or the repo.
- Every decision is logged with its reason; the after-action report summarises them for the players.
- BattlEye blocks unknown extension DLLs: run without it, or whitelist the DLL. A public server would need the DLL
  signed and whitelisted.

## Status

| Milestone | State |
| --- | --- |
| End-to-end loop (state out, decision in, action runs) | Done, tested in game |
| Waits, narration, console-spawned patrol | Tested in game |
| Antistasi-template patrols | Built, not tested in game |
| `call_support`, `offer_mission`, `launch_offensive`, `reveal_enemies`, `reward_rebels`, `change_weather` | Built, tested against Claude with sample states, not in game |
| Host requests (`AID_request`, `!director ...`) | Built, tested against Claude, not in game |
| Chat commands | Built, not tested in game |
| Campaign memory (reports, story so far) | Built, tested on a real session log |
| Comfort: skipping unchanged states, personalities, soldier cap | Built; personalities tested against Claude, the rest by unit tests; not in game |

## Next

1. **Test session** on a throwaway Antistasi save: every action, the chat commands, a session report.
2. **Real game setup** with the group's mod list (`.hemtt\presets\infinizo.html`): load the mod as a local
   mod on the host, BattlEye off, and start the companion with the game. Sessions will start on the host's own PC
   (companion and Arma side by side); a dedicated server may follow, which needs the companion and its Claude
   login (or an API key) on that machine.
3. **Outcome feedback:** tell the director what its actions led to (patrol contact and losses, what support
   Antistasi sent or that it sent nothing, missions taken up or finished) and recent events (players downed,
   towns changing hands, attacks starting and ending), plus where players are in Antistasi's world (nearest
   location and its owner, distance from HQ, vehicle). Reports then describe what happened, not only what was sent.
4. **More encounters:** vehicle patrols, roadblocks, helicopter recon, sniper teams, informants and deserters,
   supply drops, an enemy VIP.
5. **Story arcs:** short multi-step plots planned across several decisions, building on 3 and the campaign story.
6. **Comfort and cost (done):** Claude is skipped while nothing important changes (asked at least every 5
   minutes, and always for a host request), four personalities (`--personality`, `!director style`), and a cap on
   director-spawned soldiers alive (`AID_maxDirectorUnits`, checked by the companion and the game).

## Open questions

Saved for later (2026-10-22). Hosting is settled for now: the host's own PC, possibly a dedicated server later.

1. How much should the director see? It currently gets enemy counts near each player, which is more than
   Antistasi's enemy commander knows. Fine for a game master; revisit if it feels unfair.
2. When to switch from propose to auto mode, once the actions are trusted.
