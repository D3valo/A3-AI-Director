/*
    A sniper and spotter from the side's faction template (for the war level) on high ground 400-800 m from the
    named player, with a line of sight to them where the terrain allows, lying in wait. Costs attack resources;
    despawns once no rebels are near. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "sniper_team"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] sniper_team: needs Antistasi" };
if !([2, "sniper_team"] call AID_fnc_capAllows) exitWith {};

// The highest of 80 spots that can see the player; failing that (the player may be among buildings), one that
// overlooks the ground around them; failing that, the highest spot.
private _targetEye = eyePos _target;
private _around = [0, 90, 180, 270] apply { (AGLToASL (_target getPos [40, _x])) vectorAdd [0, 0, 1.5] };
private _best = [];
private _bestScore = -1e9;
for "_i" from 1 to 80 do {
    private _candidate = _target getPos [400 + random 400, random 360];
    if (surfaceIsWater _candidate) then { continue };
    private _eye = (AGLToASL _candidate) vectorAdd [0, 0, 0.6];
    private _sees = ([objNull, "VIEW"] checkVisibility [_eye, _targetEye]) > 0.3;
    private _overlooks = _around findIf { ([objNull, "VIEW"] checkVisibility [_eye, _x]) > 0.3 } >= 0;
    private _score = getTerrainHeightASL _candidate + ([0, 1000] select _overlooks) + ([0, 2000] select _sees);
    if (_score > _bestScore) then { _best = _candidate; _bestScore = _score };
};
if (_best isEqualTo []) exitWith { diag_log "[AI Director] sniper_team: no position found" };

private _types = [_faction get "groupTierSniper"] call SCRT_fnc_unit_getTiered;
private _group = [_side, _types, _best] call AID_fnc_spawnInfantry;
{ _x setUnitPos "DOWN" } forEach units _group;
_group setBehaviour "STEALTH";
_group setCombatMode "RED";
private _waypoint = _group addWaypoint [_best, 0];
_waypoint setWaypointType "HOLD";
_group reveal [_target, 1.5];
[_group] spawn A3A_fnc_groupDespawner;
["sniper_team", _side, _playerName, [_group]] call AID_fnc_trackEncounter;

diag_log format ["[AI Director] Sniper team at %1, %2 m from %3, %4",
    _best, round (_best distance2D _target), _playerName,
    ["no line of sight", "overlooking the ground around them", "line of sight"] select (floor (_bestScore / 1000) min 2)];
