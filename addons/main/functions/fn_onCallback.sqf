/*
    ExtensionCallback handler: receives the companion's decision (or an error) from the extension.
*/
params ["_name", "_function", "_data"];
if (_name != "ai_director") exitWith {};
// For the self-test, which pauses the director and waits for a reply.
AID_lastCallback = [diag_tickTime, _function, _data];

if (_function == "error") exitWith {
    diag_log format ["[AI Director] Companion error: %1", _data];
};
if (_function != "decision" || {!AID_enabled}) exitWith {};

private _decision = fromJSON _data;
if !(_decision isEqualType createHashMap) exitWith {
    diag_log format ["[AI Director] Malformed decision: %1", _data];
};
// The companion says which style it used. If the state asked for one it doesn't know (a custom name set in
// chat), say so and go back to the campaign's own, unless the style has been changed again since.
private _asked = missionNamespace getVariable ["AID_sentStyle", ""];
AID_lastStyle = _decision getOrDefault ["personality", _asked];
if (_asked != "" && { AID_lastStyle != _asked }) then {
    [format ["[Director] The companion doesn't know the style '%1'; using '%2'.", _asked, AID_lastStyle]]
        remoteExec ["systemChat", 0];
    if (AID_personality == _asked) then { AID_personality = "" };
};
private _action = _decision getOrDefault ["action", "wait"];
private _reason = _decision getOrDefault ["reason", ""];
diag_log format ["[AI Director] Decision %1: %2", _action, _reason];
if (_action == "wait") exitWith {};

if (AID_mode == "auto") then {
    _decision call AID_fnc_dispatch;
} else {
    AID_pending = _decision;
    [format ["[Director] Proposes %1: %2 Type !approve or !deny.", _action, _reason]]
        remoteExec ["systemChat", 0];
};
