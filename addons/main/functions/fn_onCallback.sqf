/*
    ExtensionCallback handler: receives the companion's decision (or an error) from the extension.
*/
params ["_name", "_function", "_data"];
if (_name != "ai_director") exitWith {};

if (_function == "error") exitWith {
    diag_log format ["[AI Director] Companion error: %1", _data];
};
if (_function != "decision" || {!AID_enabled}) exitWith {};

private _decision = fromJSON _data;
if !(_decision isEqualType createHashMap) exitWith {
    diag_log format ["[AI Director] Malformed decision: %1", _data];
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
