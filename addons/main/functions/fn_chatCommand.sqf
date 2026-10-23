/*
    Runs a chat command sent by a player's machine (see AID_fnc_initChat). Server only.

    Allowed: the host (the server's own player), logged-in or voted admins, and players whose UID is in
    AID_chatUIDs. Replies go to the sender only.

        !director <anything else>   ask the director for something (sets AID_request)
        !director help | status | on | off | auto | propose
        !director style [balanced | cinematic | merciless | supportive | default]
        !director test [full]       run the self-test against the sender (see AID_fnc_selfTest)
        !director arc [idea | status | stop]  plan a story arc from the idea (or the director's own), show the
                                    running one, or stop it
        !director hq [off | director | all]   protection of the rebel HQ (see AID_fnc_init)
        !director cooldowns [on | off]        the director's cooldowns (off: any action at any time)
        !director note <fact> | notes | notes clear   standing facts the director keeps in mind this session
        !director give rebels money|recruits <n>      resources at once, no cooldown (negative takes away)
        !director give occupants|invaders attack|defence <n>
        !director aggression occupants|invaders <points> [minutes]   change an enemy's aggression (default 30 min)
        !approve                    run the proposed decision
        !deny                       drop the proposed decision

    Arguments:
    0: The chat line <STRING>
*/
if (!isServer) exitWith {};
params [["_text", "", [""]]];

private _owner = remoteExecutedOwner;
private _sender = allPlayers param [allPlayers findIf { owner _x == _owner }, objNull];
private _reply = { [format ["[Director] %1", _this]] remoteExec ["systemChat", _owner] };

private _allowed = _owner == 2 || { admin _owner > 0 } || { getPlayerUID _sender in AID_chatUIDs };
if (!_allowed) exitWith { "Only the host or an admin can direct the director." call _reply };

private _words = _text splitString " ";
private _command = toLower (_words param [0, ""]);
private _rest = (_words select [1]) joinString " ";

switch (_command) do {
    case "!approve": {
        if (isNil "AID_pending") exitWith { "Nothing to approve." call _reply };
        [] call AID_fnc_approve;
        "Approved." call _reply;
    };
    case "!deny": {
        if (isNil "AID_pending") exitWith { "Nothing to deny." call _reply };
        ["proposal", format ["The host denied your %1", AID_pending getOrDefault ["action", "?"]]] call AID_fnc_event;
        AID_pending = nil;
        "Proposal dropped." call _reply;
    };
    case "!director": {
        private _styles = ["balanced", "cinematic", "merciless", "supportive"];
        // The style asked for in chat, else the one the companion last used (its campaign's), if known yet.
        private _style = [missionNamespace getVariable ["AID_lastStyle", "the campaign's own"], AID_personality]
            select (AID_personality != "");
        if ((toLower (_words param [1, ""])) == "test") exitWith {
            if (isNull _sender) exitWith { "The self-test needs a player to test against." call _reply };
            [name _sender, (toLower (_words param [2, ""])) == "full", _owner] spawn AID_fnc_selfTest;
        };
        if ((toLower (_words param [1, ""])) == "arc") exitWith {
            private _idea = (_words select [2]) joinString " ";
            switch (toLower _idea) do {
                case "status": {
                    (["No story arc is running.", format ["Story arc: %1.", AID_arcStatus]] select (AID_arcStatus != ""))
                        call _reply;
                };
                case "stop": { AID_arcRequest = ["stop", ""]; AID_arcOwner = _owner; "Stopping the story arc." call _reply };
                default {
                    AID_arcRequest = ["start", _idea];
                    AID_arcOwner = _owner;
                    "Planning a story arc; that takes a minute. You'll get its title here." call _reply;
                };
            };
        };
        if ((toLower (_words param [1, ""])) == "give") exitWith {
            _words params ["", "", ["_who", ""], ["_what", ""], ["_amount", ""]];
            _who = toLower _who; _what = toLower _what;
            private _n = parseNumber _amount;
            if (isNil "A3A_fnc_resourcesFIA") exitWith { "Giving resources needs Antistasi." call _reply };
            if (_n == 0) exitWith { "Usage: !director give rebels money|recruits <n>, or give occupants|invaders attack|defence <n>" call _reply };
            switch (true) do {
                case (_who == "rebels" && { _what in ["money", "recruits"] }): {
                    ([[0, _n], [_n, 0]] select (_what == "recruits")) call A3A_fnc_resourcesFIA;
                    ["host", format ["The host gave the rebels %1 %2", _n, _what]] call AID_fnc_event;
                    format ["Rebels: %1 %2.", _n, _what] call _reply;
                };
                case (_who in ["occupants", "invaders"] && { _what in ["attack", "defence"] }): {
                    private _side = ([_who] call AID_fnc_enemyFaction) select 0;
                    [_n, _side, _what] call A3A_fnc_addEnemyResources;
                    ["host", format ["The host gave the %1 %2 %3 resources", _who, _n, _what]] call AID_fnc_event;
                    format ["%1: %2 %3 resources.", _who, _n, _what] call _reply;
                };
                default { "Usage: !director give rebels money|recruits <n>, or give occupants|invaders attack|defence <n>" call _reply };
            };
        };
        if ((toLower (_words param [1, ""])) == "aggression") exitWith {
            _words params ["", "", ["_who", ""], ["_points", ""], ["_minutes", "30"]];
            _who = toLower _who;
            private _n = parseNumber _points;
            if (!(_who in ["occupants", "invaders"]) || { _n == 0 }) exitWith {
                "Usage: !director aggression occupants|invaders <points, e.g. 20 or -20> [minutes, default 30]" call _reply;
            };
            if (isNil "A3A_fnc_addAggression") exitWith { "Aggression needs Antistasi." call _reply };
            [_who, _n, (parseNumber _minutes) max 1, "host"] call AID_fnc_changeAggression;
            format ["%1 aggression %2 for %3 min.", _who, ["", "+"] select (_n > 0), (parseNumber _minutes) max 1] call _reply;
        };
        if ((toLower (_words param [1, ""])) == "note") exitWith {
            private _fact = (_words select [2]) joinString " ";
            if (_fact == "") exitWith { "Usage: !director note <a fact the director should keep in mind>" call _reply };
            AID_notes pushBack (_fact select [0, 200]);
            if (count AID_notes > 5) then { AID_notes deleteAt 0 };
            format ["Noted (%1 of at most 5): %2", count AID_notes, _fact] call _reply;
        };
        if ((toLower (_words param [1, ""])) == "notes") exitWith {
            if ((toLower (_words param [2, ""])) == "clear") exitWith { AID_notes = []; "Notes cleared." call _reply };
            (["No notes.", format ["Notes: %1", AID_notes joinString " | "]] select (AID_notes isNotEqualTo [])) call _reply;
        };
        if ((toLower (_words param [1, ""])) == "hq") exitWith {
            private _choice = toLower (_words param [2, ""]);
            private _meaning = createHashMapFromArray [
                ["off", "the HQ is not protected"],
                ["director", "the director won't attack the HQ or players at it"],
                ["all", "neither the director nor Antistasi will attack the HQ"]
            ];
            if (_choice in _meaning) then { AID_protectHQ = _choice };
            format ["HQ protection: %1 (%2). Options: off, director, all.", AID_protectHQ, _meaning get AID_protectHQ]
                call _reply;
        };
        if ((toLower (_words param [1, ""])) == "cooldowns") exitWith {
            private _choice = toLower (_words param [2, ""]);
            if (_choice in ["on", "off"]) then { AID_cooldowns = _choice == "on" };
            format ["Cooldowns: %1 (%2), from the next decision. Options: on, off.", ["off", "on"] select AID_cooldowns,
                ["any action at any time", "each action waits its cooldown"] select AID_cooldowns] call _reply;
        };
        if ((toLower (_words param [1, ""])) == "style") exitWith {
            private _choice = toLower (_words param [2, ""]);
            // Custom styles live in the companion's personalities.toml, so any one-word name is passed on; the
            // companion's next reply says if it doesn't know it (see AID_fnc_onCallback).
            switch (true) do {
                case (_choice == ""): {
                    format ["Style: %1. Built in: %2; custom ones from personalities.toml; or default.",
                        _style, _styles joinString ", "] call _reply;
                };
                case (_choice == "default"): { AID_personality = ""; "Style: the campaign's own, from the next decision." call _reply };
                case (count _choice > 32): { "Style names are one short word." call _reply };
                default { AID_personality = _choice; format ["Style: %1, from the next decision.", _choice] call _reply };
            };
        };
        switch (toLower _rest) do {
            case "";
            case "help": {
                "!director <what you want> | status | on | off | auto | propose | style <name> | hq <off/director/all> | cooldowns <on/off> | arc [idea/status/stop] | note <fact> | notes [clear] | give <side> <what> <n> | aggression <side> <n> [min] | test [full]. !approve / !deny answer a proposal." call _reply;
            };
            case "status": {
                format [
                    "%1, %2 mode, every %3 s, style %4, HQ protection %8, cooldowns %9. Director soldiers alive: %5 of %6. Proposal waiting: %7.",
                    ["off", "on"] select AID_enabled, AID_mode, AID_interval, _style,
                    [] call AID_fnc_directorUnits, AID_maxDirectorUnits, ["no", "yes"] select !isNil "AID_pending", AID_protectHQ,
                    ["off", "on"] select AID_cooldowns
                ] call _reply;
            };
            case "on": { AID_enabled = true; "On." call _reply };
            case "off": { AID_enabled = false; AID_pending = nil; "Off." call _reply };
            case "auto": {
                AID_mode = "auto";
                (["Decisions now run at once.", "Decisions now run at once. One proposal is still waiting: !approve or !deny it."]
                    select !isNil "AID_pending") call _reply;
            };
            case "propose": { AID_mode = "propose"; "Decisions now wait for !approve." call _reply };
            default {
                AID_request = _rest;
                AID_requestOwner = _owner;
                format ["Request sent: %1. You'll hear here what the director makes of it.", _rest] call _reply;
            };
        };
    };
};
diag_log format ["[AI Director] Chat command from %1: %2", name _sender, _text];
