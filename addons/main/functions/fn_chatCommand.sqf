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
                "!director <what you want> | status | on | off | auto | propose | style <name> | hq <off/director/all> | arc [idea/status/stop] | test [full]. !approve / !deny answer a proposal." call _reply;
            };
            case "status": {
                format [
                    "%1, %2 mode, every %3 s, style %4, HQ protection %8. Director soldiers alive: %5 of %6. Proposal waiting: %7.",
                    ["off", "on"] select AID_enabled, AID_mode, AID_interval, _style,
                    [] call AID_fnc_directorUnits, AID_maxDirectorUnits, ["no", "yes"] select !isNil "AID_pending", AID_protectHQ
                ] call _reply;
            };
            case "on": { AID_enabled = true; "On." call _reply };
            case "off": { AID_enabled = false; AID_pending = nil; "Off." call _reply };
            case "auto": { AID_mode = "auto"; "Decisions now run at once." call _reply };
            case "propose": { AID_mode = "propose"; "Decisions now wait for !approve." call _reply };
            default {
                AID_request = _rest;
                format ["Request sent: %1", _rest] call _reply;
            };
        };
    };
};
diag_log format ["[AI Director] Chat command from %1: %2", name _sender, _text];
