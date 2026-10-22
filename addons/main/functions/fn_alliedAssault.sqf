/*
    Rebel AI assaults an enemy-held location near the named player: a fireteam or squad from the rebels' template
    appears 300-600 m from the player, out of sight, and attacks the named location (or the enemy-held one nearest
    the player, within 3 km). The rebel commander gets it under high command. A gift from the director; taking the
    location is up to the fight, as Antistasi decides captures. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Strength, "fireteam" or "squad" <STRING>
    2: Location name as the director knows it, or "" for the nearest enemy-held one <STRING>
*/
params ["_playerName", ["_strength", "squad"], ["_place", ""]];

private _target = [_playerName, "allied_assault"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
if (isNil "A3A_faction_reb") exitWith { diag_log "[AI Director] allied_assault: needs Antistasi" };
private _marker = [_place, _target] call AID_fnc_findPlace;
if (_marker == "") exitWith {
    ["outcome", format ["Your allied_assault near %1: no enemy-held location %2", _playerName,
        ["within 3 km", format ["called %1", _place]] select (_place != "")]] call AID_fnc_event;
};
private _pos = [_target, 300, 600] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) then { _pos = _target getPos [300, random 360] };

private _boss = missionNamespace getVariable ["theBoss", _target];
private _group = [_boss, _strength, _pos, "Director assault"] call AID_fnc_spawnRebels;
if (units _group isEqualTo []) exitWith {};
private _waypoint = _group addWaypoint [markerPos _marker, 50];
_waypoint setWaypointType "SAD";
_group setBehaviour "AWARE";
private _name = [_marker] call AID_fnc_placeName;
[format ["A rebel %1 is moving to assault %2.", _strength, _name]] remoteExec ["systemChat", 0];
["outcome", format ["Your allied_assault: a rebel %1 is attacking %2", _strength, _name]] call AID_fnc_event;
