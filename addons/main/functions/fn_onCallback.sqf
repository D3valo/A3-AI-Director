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
// The story arc's progress. News of it goes only to whoever started it, so the plot isn't spoiled.
private _arc = _decision getOrDefault ["arc", createHashMap];
if (isNil "_arc" || { !(_arc isEqualType createHashMap) }) then { _arc = createHashMap };
private _title = _arc getOrDefault ["title", ""];
AID_arcStatus = ["", format ["""%1"", beat %2 of %3", _title, _arc get "beat", _arc get "beats"]] select (_title != "");
private _news = switch (_arc getOrDefault ["event", ""]) do {
    case "started": { format ["Story arc begins: ""%1"" (%2 beats). !director arc status or stop.", _title, _arc get "beats"] };
    case "completed": { format ["Story arc complete: ""%1"".", _title] };
    case "stopped": { format ["Story arc stopped: ""%1"".", _title] };
    case "failed": { "The companion couldn't plan a story arc; see its window." };
    default { "" };
};
if (_news != "") then { [format ["[Director] %1", _news]] remoteExec ["systemChat", AID_arcOwner] };
if ((_arc getOrDefault ["event", ""]) in ["completed", "stopped"]) then { AID_arcStatus = "" };
private _action = _decision getOrDefault ["action", "wait"];
private _reason = _decision getOrDefault ["reason", ""];
diag_log format ["[AI Director] Decision %1: %2", _action, _reason];
if (_action == "wait") exitWith {};

if (AID_mode == "auto") then {
    _decision call AID_fnc_dispatch;
} else {
    if (!isNil "AID_pending") then {
        ["proposal", format ["Your proposed %1 was never answered and was replaced", AID_pending getOrDefault ["action", "?"]]]
            call AID_fnc_event;
    };
    AID_pending = _decision;
    [format ["[Director] Proposes %1: %2 Type !approve or !deny.", _action, _reason]]
        remoteExec ["systemChat", 0];
};
