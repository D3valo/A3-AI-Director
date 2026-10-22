/*
    Runs a chat command sent by a player's machine (see AID_fnc_initChat). Server only.

    Allowed: the host (the server's own player), logged-in or voted admins, and players whose UID is in
    AID_chatUIDs. Replies go to the sender only.

        !director <anything else>   ask the director for something (sets AID_request)
        !director help | status | on | off | auto | propose
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
        switch (toLower _rest) do {
            case "";
            case "help": {
                "!director <what you want> | status | on | off | auto | propose. !approve / !deny answer a proposal." call _reply;
            };
            case "status": {
                format [
                    "%1, %2 mode, every %3 s. Proposal waiting: %4.",
                    ["off", "on"] select AID_enabled, AID_mode, AID_interval, ["no", "yes"] select !isNil "AID_pending"
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
