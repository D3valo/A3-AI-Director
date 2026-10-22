/*
    A punishing armoured response: a tank (or IFV, light tank or APC, whatever the faction has, in that order) with
    crew, plus an infantry squad in an APC or IFV's back where there is room, comes from a road 1.2-2 km from the
    named player, out of sight, and hunts around them. From the side's faction template; costs its attack resources
    (it may go into debt); despawns once no rebels are near. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "armor_assault"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] armor_assault: needs Antistasi" };
if !([11, "armor_assault"] call AID_fnc_capAllows) exitWith {};

private _pos = [_target, 1200, 2000, true] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith {
    ["outcome", format ["Your armor_assault against %1: no hidden road to come from", _playerName]] call AID_fnc_event;
};
private _spawned = [_side, _faction, ["vehiclesTanks", "vehiclesIFVs", "vehiclesLightTanks", "vehiclesAPCs"],
    _pos, _pos getDir _target] call AID_fnc_spawnVehicle;
if (_spawned isEqualTo []) exitWith {
    ["outcome", "Your armor_assault: the faction has no armour"] call AID_fnc_event;
};
_spawned params ["_vehicle", "_crew"];

private _seats = _vehicle emptyPositions "cargo";
if (_seats > 0) then {
    private _types = selectRandom ([_faction, "groupsTierSquads"] call SCRT_fnc_unit_flattenTier);
    _types resize (_seats min count _types);
    private _cargo = [_side, _types, _pos getPos [20, random 360]] call AID_fnc_spawnInfantry;
    { _x moveInCargo _vehicle } forEach units _cargo;
    units _cargo joinSilent _crew;
};
private _waypoint = _crew addWaypoint [getPosATL _target, 150];
_waypoint setWaypointType "SAD";
[_crew] spawn A3A_fnc_groupDespawner;
[_vehicle] spawn A3A_fnc_VEHdespawner;
["armor_assault", _side, _playerName, [_crew]] call AID_fnc_trackEncounter;
diag_log format ["[AI Director] Armor assault: %1 with %2 soldiers at %3, %4 m from %5",
    typeOf _vehicle, count units _crew, _pos, round (_pos distance2D _target), _playerName];
