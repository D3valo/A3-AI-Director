/*
    Runs a chat command sent by a player's machine (see AID_fnc_initChat). Server only.

    Allowed: the host (the server's own player), logged-in or voted admins, and players whose UID is in
    AID_chatUIDs. Replies go to the sender only.

        !director <anything else>   ask the director for something (sets AID_request)
        !director help | status | on | off | auto | propose
        !director style [balanced | cinematic | merciless | supportive | default]
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
        diag_log format ["[AI Director] Denied in chat: %1", AID_pending];
        AID_pending = nil;
        "Proposal dropped." call _reply;
    };
    case "!director": {
        private _styles = ["balanced", "cinematic", "merciless", "supportive"];
        private _style = ["companion's default", AID_personality] select (AID_personality != "");
        if ((toLower (_words param [1, ""])) == "style") exitWith {
            private _choice = toLower (_words param [2, ""]);
            switch (true) do {
                case (_choice == ""): {
                    format ["Style: %1. Choose from %2, or default.", _style, _styles joinString ", "] call _reply;
                };
                case (_choice == "default"): { AID_personality = ""; "Style: the companion's default." call _reply };
                case (_choice in _styles): { AID_personality = _choice; format ["Style: %1.", _choice] call _reply };
                default { format ["Unknown style. Choose from %1, or default.", _styles joinString ", "] call _reply };
            };
        };
        switch (toLower _rest) do {
            case "";
            case "help": {
                "!director <what you want> | status | on | off | auto | propose | style <name>. !approve / !deny answer a proposal." call _reply;
            };
            case "status": {
                format [
                    "%1, %2 mode, every %3 s, style %4. Director soldiers alive: %5 of %6. Proposal waiting: %7.",
                    ["off", "on"] select AID_enabled, AID_mode, AID_interval, _style,
                    [] call AID_fnc_directorUnits, AID_maxDirectorUnits, ["no", "yes"] select !isNil "AID_pending"
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
