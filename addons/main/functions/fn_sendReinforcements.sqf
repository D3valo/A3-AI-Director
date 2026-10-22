/*
    A rebel fireteam or squad from the rebels' template arrives to join the named player: it appears 200-400 m away,
    out of sight, and moves to them, under their command (high command for the rebel commander, the player's own
    group otherwise). A gift from the director. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Strength, "fireteam" or "squad" <STRING>
*/
params ["_playerName", ["_strength", "fireteam"]];

private _target = [_playerName, "send_reinforcements"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
if (isNil "A3A_faction_reb") exitWith { diag_log "[AI Director] send_reinforcements: needs Antistasi" };
private _pos = [_target, 200, 400] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith {
    ["outcome", format ["Your send_reinforcements to %1: no hidden spot nearby, nobody came", _playerName]] call AID_fnc_event;
};

private _group = [_target, _strength, _pos, "Director reinforcements"] call AID_fnc_spawnRebels;
if (units _group isNotEqualTo []) then { _group move getPosATL _target };
[format ["Reinforcements: a rebel %1 is joining %2 from %3 m away.", _strength, _playerName, round (_pos distance2D _target)]]
    remoteExec ["systemChat", 0];
["outcome", format ["Your send_reinforcements: a rebel %1 is joining %2", _strength, _playerName]] call AID_fnc_event;
