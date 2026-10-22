/*
    Spawns a patrol 600-1000 m from the named player, out of sight of every player, and sends it to
    search and destroy around them. Scheduled environment only (Antistasi's group spawn sleeps).

    In Antistasi the patrol is a group from the side's faction template for the current war level
    (a 5-man fireteam or an 8-man squad), spawned and initialised the way Antistasi spawns its own
    patrols. It costs the side's attack resources and despawns once no rebels are near. Elsewhere it
    is built from AID_patrolUnits.

    Arguments:
    0: Player name <STRING>
    1: Strength, "fireteam" (4-5) or "squad" (8) <STRING>
    2: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", "_strength", ["_enemy", ""]];

private _target = [_playerName, "spawn_patrol"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
private _isSquad = _strength == "squad";
if !([[5, 8] select _isSquad, "spawn_patrol"] call AID_fnc_capAllows) exitWith {};

private _pos = [_target, 600, 1000] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] spawn_patrol: no hidden position found" };

([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
private _antistasi = !isNil "_faction";
private _group = grpNull;
if (_antistasi) then {
    // groupsTierMedium starts with the fireteams; the rest are sniper, AA and AT teams.
    private _types = if (_isSquad) then {
        selectRandom ([_faction, "groupsTierSquads"] call SCRT_fnc_unit_flattenTier)
    } else {
        [(_faction get "groupsTierMedium") select 0] call SCRT_fnc_unit_getTiered
    };
    _group = [_side, _types, _pos] call AID_fnc_spawnInfantry;
} else {
    _group = createGroup [_side, true];
    for "_i" from 0 to ([4, 8] select _isSquad) - 1 do {
        _group createUnit [AID_patrolUnits select (_i mod count AID_patrolUnits), _pos, [], 10, "FORM"];
    };
    AID_spawnedGroups pushBack _group;
};

private _waypoint = _group addWaypoint [getPosATL _target, 75];
_waypoint setWaypointType "SAD";
if (_antistasi) then { [_group] spawn A3A_fnc_groupDespawner };
["spawn_patrol", _side, _playerName, [_group]] call AID_fnc_trackEncounter;

diag_log format [
    "[AI Director] Spawned %1 (%2 units, %3, %4) at %5, %6 m from %7",
    _group, count units _group, _side, ["vanilla", "Antistasi template"] select _antistasi,
    _pos, round (_pos distance2D _target), _playerName
];
