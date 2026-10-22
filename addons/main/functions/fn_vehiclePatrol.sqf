/*
    An armed light vehicle with a fireteam aboard drives in from a road 900-1500 m from the named player, out of
    sight, and hunts around them. From the side's faction template; costs attack resources; despawns once no
    rebels are near. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
*/
params ["_playerName"];

private _target = [_playerName, "vehicle_patrol"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] vehicle_patrol: needs Antistasi" };
if !([8, "vehicle_patrol"] call AID_fnc_capAllows) exitWith {};

private _pos = [_target, 900, 1500, true] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] vehicle_patrol: no hidden road found" };

private _spawned = [_side, _faction, ["vehiclesLightArmed", "vehiclesMilitiaLightArmed", "vehiclesLightUnarmed"],
    _pos, _pos getDir _target] call AID_fnc_spawnVehicle;
if (_spawned isEqualTo []) exitWith {};
_spawned params ["_vehicle", "_crew"];

// A fireteam in the back, as many as there are seats.
private _seats = _vehicle emptyPositions "cargo";
if (_seats > 0) then {
    private _types = [(_faction get "groupsTierMedium") select 0] call SCRT_fnc_unit_getTiered;
    _types resize (_seats min count _types);
    private _cargo = [_side, _types, _pos getPos [15, random 360]] call AID_fnc_spawnInfantry;
    { _x moveInCargo _vehicle } forEach units _cargo;
    // One group, so the fireteam dismounts and fights with the vehicle.
    units _cargo joinSilent _crew;
};

private _waypoint = _crew addWaypoint [getPosATL _target, 100];
_waypoint setWaypointType "SAD";
[_crew] spawn A3A_fnc_groupDespawner;
[_vehicle] spawn A3A_fnc_VEHdespawner;

diag_log format ["[AI Director] Vehicle patrol: %1 with %2 soldiers at %3, %4 m from %5",
    typeOf _vehicle, count units _crew, _pos, round (_pos distance2D _target), _playerName];
