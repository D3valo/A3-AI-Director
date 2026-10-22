/*
    An enemy officer (the faction template's Official) with a fireteam escort patrols 700-1200 m from the named
    player, out of sight. Intel marks him on every map for 10 minutes, following him. If the rebels kill him while
    he is marked, sympathisers pay them 500. Costs the side attack resources; despawns once no rebels are near.
    Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "enemy_vip"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] enemy_vip: needs Antistasi" };
if !([6, "enemy_vip"] call AID_fnc_capAllows) exitWith {};

private _pos = [_target, 700, 1200] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] enemy_vip: no hidden position found" };

private _escort = [(_faction get "groupsTierMedium") select 0] call SCRT_fnc_unit_getTiered;
private _group = [_side, [_faction get "unitOfficial"] + _escort, _pos] call AID_fnc_spawnInfantry;
private _officer = units _group select 0;
_group selectLeader _officer;
_officer addEventHandler ["Killed", {
    params ["_unit", "_killer", "_instigator"];
    _unit setVariable ["AID_killer", [_killer, _instigator] select !isNull _instigator];
}];
_group setBehaviour "SAFE";
_group setSpeedMode "LIMITED";
// A slow loop around where he appeared.
for "_i" from 0 to 3 do {
    private _waypoint = _group addWaypoint [_pos getPos [150 + random 150, _i * 90 + random 45], 0];
    _waypoint setWaypointType (["MOVE", "CYCLE"] select (_i == 3));
};
[_group] spawn A3A_fnc_groupDespawner;
private _encounter = ["enemy_vip", _side, _playerName, [_group]] call AID_fnc_trackEncounter;

private _marker = createMarker [format ["AID_vip_%1", diag_tickTime], getPosATL _officer];
_marker setMarkerTypeLocal "mil_warning";
_marker setMarkerColorLocal "ColorOPFOR";
_marker setMarkerText "Enemy officer (intel)";
["Intel: an enemy officer with a small escort is out in the open; marked on the map for 10 minutes."]
    remoteExec ["systemChat", 0];
diag_log format ["[AI Director] Enemy VIP at %1, %2 m from %3", _pos, round (_pos distance2D _target), _playerName];

private _until = time + 600;
while { alive _officer && { time < _until } } do {
    _marker setMarkerPos getPosATL _officer;
    sleep 15;
};
deleteMarker _marker;
if (alive _officer) then {
    ["outcome", "The enemy officer was not caught while marked; he got away"] call AID_fnc_event;
    _encounter set ["note", "The officer got away"];
};
if (!alive _officer && { time < _until }) then {
    private _killer = _officer getVariable ["AID_killer", objNull];
    if (side group _killer == teamPlayer) then {
        [0, 500] call A3A_fnc_resourcesFIA;
        ["outcome", format ["The rebels killed the enemy officer (%1); sympathisers paid 500", name _killer]]
            call AID_fnc_event;
        _encounter set ["note", "The officer was killed by the rebels"];
        ["The officer is dead. Sympathisers have sent 500 for the job."] remoteExec ["systemChat", 0];
        diag_log "[AI Director] Enemy VIP killed by the rebels";
    };
};
