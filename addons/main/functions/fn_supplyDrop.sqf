/*
    Sympathisers parachute a captured enemy supply crate 100-200 m from the named player: the side's own ammo box,
    filled by Antistasi's loot crate fill (unlock-aware), loadable into vehicles, marked on the map for 10 minutes
    and with green smoke when it lands. Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
*/
params ["_playerName"];

private _target = [_playerName, "supply_drop"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] supply_drop: needs Antistasi" };

private _pos = [];
for "_i" from 1 to 20 do {
    private _candidate = _target getPos [100 + random 100, random 360];
    if (!surfaceIsWater _candidate) exitWith { _pos = _candidate };
};
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] supply_drop: only water nearby" };

private _crate = [_faction get "ammobox", _pos, 150] call SCRT_fnc_common_airdropCargo;
if (isNull _crate) exitWith { diag_log "[AI Director] supply_drop: crate could not be dropped" };
[_crate, teamPlayer] call A3A_fnc_AIVEHinit;
[_crate] call A3A_Logistics_fnc_addLoadAction;
[_crate] spawn A3A_fnc_fillLootCrate;

private _marker = createMarker [format ["AID_drop_%1", diag_tickTime], _pos];
_marker setMarkerTypeLocal "mil_pickup";
_marker setMarkerColorLocal "ColorGUER";
_marker setMarkerText "Supply drop";
["Sympathisers are dropping a supply crate nearby: marked on the map, green smoke when it lands."]
    remoteExec ["systemChat", 0];
diag_log format ["[AI Director] Supply drop near %1 at %2", _playerName, _pos];

waitUntil { sleep 2; isNull _crate || { (getPosATL _crate select 2) < 2 } };
if (!isNull _crate) then {
    createVehicle ["SmokeShellGreen", getPosATL _crate, [], 0, "CAN_COLLIDE"];
    _marker setMarkerPos getPosATL _crate;
};
sleep 600;
deleteMarker _marker;
