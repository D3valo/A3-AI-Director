/*
    A roadblock on a road 500-900 m ahead of the named player: an armed light vehicle across the road and a
    fireteam holding it, out of sight when placed. "Ahead" is the direction the player (or their vehicle) is
    moving, or any direction if they are standing still. From the side's faction template; costs attack
    resources; despawns once no rebels are near. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "roadblock"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] roadblock: needs Antistasi" };
if !([8, "roadblock"] call AID_fnc_capAllows) exitWith {};

private _moving = vehicle _target;
private _bearing = [-1, getDir _moving] select (speed _moving > 5);
private _pos = [_target, 500, 900, true, true, _bearing, 50] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] roadblock: no hidden road found ahead" };

// Across the road: roads point along themselves, so turn the vehicle a quarter.
private _road = roadAt _pos;
private _across = [random 360, getDir _road + 90] select !isNull _road;
private _spawned = [_side, _faction, ["vehiclesLightArmed", "vehiclesMilitiaLightArmed", "vehiclesLightUnarmed"],
    _pos, _across] call AID_fnc_spawnVehicle;
if (_spawned isEqualTo []) exitWith {};
_spawned params ["_vehicle", "_crew"];

private _types = [(_faction get "groupsTierMedium") select 0] call SCRT_fnc_unit_getTiered;
private _guards = [_side, _types, _pos getPos [12, _across + 90]] call AID_fnc_spawnInfantry;
{
    private _waypoint = _x addWaypoint [_pos, 0];
    _waypoint setWaypointType "HOLD";
    _x setBehaviour "AWARE";
    [_x] spawn A3A_fnc_groupDespawner;
} forEach [_crew, _guards];
[_vehicle] spawn A3A_fnc_VEHdespawner;
["roadblock", _side, _playerName, [_crew, _guards]] call AID_fnc_trackEncounter;

diag_log format ["[AI Director] Roadblock: %1 and %2 soldiers at %3, %4 m from %5",
    typeOf _vehicle, count units _crew + count units _guards, _pos, round (_pos distance2D _target), _playerName];
