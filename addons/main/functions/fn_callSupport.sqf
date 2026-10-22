/*
    Has Antistasi's enemy react to the named player as if one of its units had spotted them and called for
    support. Antistasi's own support logic (A3A_fnc_requestSupport) picks a QRF, artillery, air support
    or nothing, from the side's defence resources and its checks for friendlies and civilians nearby.
    Scheduled environment only.

    Side: AID_patrolSide if set, otherwise Occupants.

    Arguments:
    0: Player name <STRING>
*/
params ["_playerName"];

if (isNil "A3A_fnc_requestSupport") exitWith { diag_log "[AI Director] call_support: Antistasi is not running" };
private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] call_support: no player named %1", _playerName] };
_target = allPlayers select _target;
private _side = missionNamespace getVariable ["AID_patrolSide", Occupants];

diag_log format ["[AI Director] Requesting %1 support against %2 at %3", _side, _playerName, getPosATL _target];
// Precision 3 of 4: the spotter knows roughly where they are. Reveal 0.5: players may hear the call.
[_side, _target, getPosATL _target, 3, 0.5] call A3A_fnc_requestSupport;
