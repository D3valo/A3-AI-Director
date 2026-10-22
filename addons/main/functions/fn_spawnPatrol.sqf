/*
    Spawns an AID_patrolSide patrol 600-1000 m from the named player, out of sight of every player,
    and sends it to search and destroy around them.

    Arguments:
    0: Player name <STRING>
    1: Strength, "fireteam" (4) or "squad" (8) <STRING>
*/
params ["_playerName", "_strength"];

private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] spawn_patrol: no player named %1", _playerName] };
_target = allPlayers select _target;
private _size = [4, 8] select (_strength == "squad");

private _hiddenFromPlayers = {
    params ["_pos"];
    private _eye = (AGLToASL _pos) vectorAdd [0, 0, 1.7];
    allPlayers findIf {
        _x distance2D _pos < 1500 && { ([objNull, "VIEW"] checkVisibility [eyePos _x, _eye]) > 0.1 }
    } < 0
};

private _pos = [];
for "_i" from 1 to 30 do {
    private _candidate = _target getPos [600 + random 400, random 360];
    if (!surfaceIsWater _candidate && { [_candidate] call _hiddenFromPlayers }) exitWith { _pos = _candidate };
};
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] spawn_patrol: no hidden position found" };

private _group = createGroup [AID_patrolSide, true];
for "_i" from 0 to (_size - 1) do {
    _group createUnit [AID_patrolUnits select (_i mod count AID_patrolUnits), _pos, [], 10, "FORM"];
};
private _waypoint = _group addWaypoint [getPosATL _target, 75];
_waypoint setWaypointType "SAD";
diag_log format ["[AI Director] Spawned %1 (%2 units) at %3, %4 m from %5", _group, _size, _pos, round (_pos distance2D _target), _playerName];
