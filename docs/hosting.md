# Hosting real sessions

The director runs where the game is hosted: the mod and its extension on the server, the companion beside it.
Players join as usual and need nothing extra.

## On the host's own PC (now)

The host plays and hosts from the same PC, with the group's mod list (`.hemtt\presets\infinizo.html`, an export
from the Arma 3 Launcher; every mod in it must be downloaded on this PC).

**Once, and after each update of the director:**

```powershell
tools\install.cmd          # tests, builds and installs the mod to ModDir (see below; Arma closed)
```

**Each session** (from any terminal, or double-click the `.cmd` in Explorer):

```powershell
tools\start-session.cmd                          # -Personality <style> (remembered), -Campaign <name>, -NoNarrative, -DryRun
```

It checks that every mod in the preset is downloaded, opens the companion in its own window (campaign
`infinizo`), and starts Arma 3 with the preset's mods plus the director. Then:

1. Host from **Multiplayer**, load the Antistasi save, and play. `!director status` in chat confirms the
   director is on.
2. The other players start Arma from the launcher with the same preset, as usual, and join.
3. After the session, press Ctrl+C in the companion window and wait for the report
   (`companion\campaigns\infinizo\reports\`).

Notes:

- **Where the mod goes:** `ModDir` in `tools\local-settings.psd1` (not in git; copy `local-settings.example.psd1`),
  else `install\@AIDirector` in the repo. Both scripts use it.
- **BattlEye** must be off on the host: Arma only loads extensions BattlEye knows, and BattlEye doesn't know this
  one. `start-session.ps1` starts the game directly, which leaves BattlEye off. Players' own BattlEye setting doesn't
  matter for joining a server without it.
- **Starting from the launcher instead:** add the installed mod folder (`ModDir`) once as a local mod
  (Mods > More > Add local mod), tick it in the preset, untick **Enable BattlEye** under Parameters, and start the
  companion with `tools\start-session.cmd -NoGame`.
- **When the mod list changes:** export the preset from the launcher over `.hemtt\presets\infinizo.html`, used by
  both `start-session.ps1` and `hemtt launch infinizo` (test sessions).
- **The Claude login** on this PC pays for the decisions (the `claude-code` backend). That's for your own group's
  games; see the README.

## On a dedicated server (later)

What changes when the group moves to a dedicated server:

| Concern | What to do |
| --- | --- |
| Mod | Copy `@AIDirector` to the server and load it with `-serverMod=@AIDirector` (server only; not in `-mod`, so players aren't asked for it) |
| Mods for players | The preset's mods with `-mod=` as usual; players keep joining with the preset |
| BattlEye | `BattlEye = 0;` in `server.cfg`, or keep BattlEye and have the DLL whitelisted (needs the DLL signed and submitted to BattlEye; not practical for a private mod) |
| Companion | On the server machine, next to Arma: Python 3.13 venv from `companion\requirements.txt`, started before the mission (a scheduled task or service rather than a window). The extension only talks to 127.0.0.1 |
| Claude | Either Claude Code installed and logged in on the server with the host's own subscription (`claude-code` backend; still only for the group's own games), or an API key with a spending limit (`--backend api`), which is the cleaner choice for an unattended machine |
| Chat commands | Work as before for logged-in admins (`#login`) and `AID_chatUIDs`; there is no host player, so add the organisers' UIDs |
| Linux server | The extension is built for Windows (`ai_director_x64.dll`). A Linux server needs a Linux build (`ai_director_x64.so`, `cargo build --target x86_64-unknown-linux-gnu`; arma-rs supports it) and a Linux companion; not built yet |
| Reports | The companion writes them on the server; copy `companion\campaigns\<name>` back or run the companion's `report` command there |
