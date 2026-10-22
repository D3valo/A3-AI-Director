/*
    A punishing air response: an attack helicopter (or armed light helicopter) from the side's faction template flies
    in from 3-4 km and hunts around the named player for up to 10 minutes, then leaves. Costs the side's attack
    resources (it may go into debt). Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "air_attack"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] air_attack: needs Antistasi" };
if !([4, "air_attack"] call AID_fnc_capAllows) exitWith {};

private _start = (_target getPos [3000 + random 1000, random 360]) vectorAdd [0, 0, 200];
private _spawned = [_side, _faction, ["vehiclesHelisAttack", "vehiclesHelisLightAttack"], _start,
    _start getDir _target, "FLY"] call AID_fnc_spawnVehicle;
if (_spawned isEqualTo []) exitWith {
    ["outcome", "Your air_attack: the faction has no attack helicopters"] call AID_fnc_event;
};
_spawned params ["_heli", "_crew"];
_heli flyInHeight 120;
_crew setCombatMode "RED";
_crew setBehaviour "COMBAT";
private _waypoint = _crew addWaypoint [getPosATL _target, 300];
_waypoint setWaypointType "SAD";
private _encounter = ["air_attack", _side, _playerName, [_crew]] call AID_fnc_trackEncounter;
diag_log format ["[AI Director] Air attack: %1 inbound to %2", typeOf _heli, _playerName];

// Hunt for up to 10 minutes, then go home and disappear out of sight.
private _until = time + 600;
waitUntil { sleep 10; !alive _heli || { time > _until } };
if (!alive _heli) exitWith { _encounter set ["note", "The helicopter was shot down"] };
_encounter set ["note", "The helicopter hunted for 10 minutes and left"];
_crew move (_heli getPos [6000, _target getDir _heli]);
waitUntil { sleep 5; !alive _heli || { allPlayers findIf { _x distance2D _heli < 3000 } < 0 } };
if (alive _heli) then {
    { deleteVehicle _x } forEach units _crew;
    deleteVehicle _heli;
};
