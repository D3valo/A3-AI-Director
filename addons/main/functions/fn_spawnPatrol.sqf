/*
    Spawns a patrol 600-1000 m from the named player, out of sight of every player, and sends it to
    search and destroy around them. Scheduled environment only (Antistasi's group spawn sleeps).

    In Antistasi the patrol is a group from the side's faction template for the current war level
    (a 5-man fireteam or an 8-man squad), spawned and initialised the way Antistasi spawns its own
    patrols. It costs the side's attack resources and despawns once no rebels are near. Elsewhere it
    is built from AID_patrolUnits.

    Side: AID_patrolSide if set, otherwise Antistasi's Occupants, otherwise east.

    Arguments:
    0: Player name <STRING>
    1: Strength, "fireteam" (4-5) or "squad" (8) <STRING>
*/
params ["_playerName", "_strength"];

private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] spawn_patrol: no player named %1", _playerName] };
_target = allPlayers select _target;
private _isSquad = _strength == "squad";
private _side = missionNamespace getVariable ["AID_patrolSide", missionNamespace getVariable ["Occupants", east]];

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

private _antistasi = !isNil "A3A_fnc_spawnGroup" && { _side in [missionNamespace getVariable "Occupants", missionNamespace getVariable "Invaders"] };
private _group = grpNull;
if (_antistasi) then {
    private _faction = [A3A_faction_inv, A3A_faction_occ] select (_side == Occupants);
    // groupsTierMedium starts with the fireteams; the rest are sniper, AA and AT teams.
    private _types = if (_isSquad) then {
        selectRandom ([_faction, "groupsTierSquads"] call SCRT_fnc_unit_flattenTier)
    } else {
        [(_faction get "groupsTierMedium") select 0] call SCRT_fnc_unit_getTiered
    };
    _group = [_pos, _side, _types] call A3A_fnc_spawnGroup;
    { [_x, "", false, "attack"] call A3A_fnc_NATOinit } forEach units _group;
    [-10 * count units _group, _side, "attack"] call A3A_fnc_addEnemyResources;
} else {
    _group = createGroup [_side, true];
    for "_i" from 0 to ([4, 8] select _isSquad) - 1 do {
        _group createUnit [AID_patrolUnits select (_i mod count AID_patrolUnits), _pos, [], 10, "FORM"];
    };
};

private _waypoint = _group addWaypoint [getPosATL _target, 75];
_waypoint setWaypointType "SAD";
if (_antistasi) then { [_group] spawn A3A_fnc_groupDespawner };

diag_log format [
    "[AI Director] Spawned %1 (%2 units, %3, %4) at %5, %6 m from %7",
    _group, count units _group, _side, ["vanilla", "Antistasi template"] select _antistasi,
    _pos, round (_pos distance2D _target), _playerName
];
