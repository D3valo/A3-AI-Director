/*
    Runs the decision proposed in "propose" mode. Server exec from the debug console:
        [] call AID_fnc_approve;
*/
if (!isServer) exitWith {};
if (isNil "AID_pending") exitWith { diag_log "[AI Director] Nothing to approve." };
private _decision = AID_pending;
AID_pending = nil;
["proposal", format ["The host approved your %1", _decision getOrDefault ["action", "?"]]] call AID_fnc_event;
_decision call AID_fnc_dispatch;
