/*
    Has Antistasi's enemy react to the named player as if one of its units had spotted them and called for
    support. Antistasi's own support logic (A3A_fnc_requestSupport) picks a QRF, artillery, air support
    or nothing, from the side's defence resources and its checks for friendlies and civilians nearby.
    Scheduled environment only.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", ["_enemy", ""]];

if (isNil "A3A_fnc_requestSupport") exitWith { diag_log "[AI Director] call_support: Antistasi is not running" };
private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] call_support: no player named %1", _playerName] };
_target = allPlayers select _target;
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;

diag_log format ["[AI Director] Requesting %1 support against %2 at %3", _side, _playerName, getPosATL _target];
private _strikesBefore = +(missionNamespace getVariable ["A3A_supportStrikes", []]);
private _activeBefore = +(missionNamespace getVariable ["A3A_activeSupports", []]);
// Precision 3 of 4: the spotter knows roughly where they are. Reveal 0.5: players may hear the call.
[_side, _target, getPosATL _target, 3, 0.5] call A3A_fnc_requestSupport;

// What Antistasi sent: a new active support (by type) or a new strike (by class), or nothing.
private _types = ((missionNamespace getVariable ["A3A_activeSupports", []]) select { !(_x in _activeBefore) })
    apply { _x select 2 };
private _classes = ((missionNamespace getVariable ["A3A_supportStrikes", []]) select { !(_x in _strikesBefore) })
    apply { _x select 1 };
private _sent = [_types, _classes] select (_types isEqualTo []);
["outcome", [
    format ["Your call_support (%1) against %2: Antistasi sent nothing (no affordable or safe support)",
        [_side] call AID_fnc_sideName, _playerName],
    format ["Your call_support (%1) against %2: Antistasi sent %3", [_side] call AID_fnc_sideName, _playerName,
        _sent joinString ", "]
] select (_sent isNotEqualTo [])] call AID_fnc_event;
