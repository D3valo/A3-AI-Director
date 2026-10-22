/*
    Installs the chat commands. Server only.

    The mod runs on the server alone, so the client side is sent as code to every machine with an
    interface, including players who join later (JIP). It hides director commands from every player's
    chat, and the sender's machine passes the command to AID_fnc_chatCommand on the server, which
    checks who sent it.
*/
if (!isServer) exitWith {};

private _clientInit = {
    if (!hasInterface || {!isNil "AID_chatHandler"}) exitWith {};
    AID_chatHandler = addMissionEventHandler ["HandleChatMessage", {
        params ["", "", "", "_text", "_person"];
        private _command = toLower ((_text splitString " ") param [0, ""]);
        if !(_command in ["!director", "!approve", "!deny"]) exitWith { false };
        if (_person isEqualTo player) then { [_text] remoteExec ["AID_fnc_chatCommand", 2] };
        true
    }];
};
[[], _clientInit] remoteExec ["call", 0, "AID_chatInit"];
