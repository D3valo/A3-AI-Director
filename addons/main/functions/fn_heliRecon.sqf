/*
    A light helicopter from the side's faction template flies in from 3 km, circles the named player for two
    minutes without firing, and leaves. While it is overhead, enemy groups within 2 km of the players it can see
    learn where they are. Costs attack resources like any vehicle; deleted once it is far from every player.
    Antistasi only; scheduled.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_playerName", ["_enemy", ""]];

private _target = [_playerName, "heli_recon"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
([_enemy] call AID_fnc_enemyFaction) params ["_side", "_faction"];
if (isNil "_faction") exitWith { diag_log "[AI Director] heli_recon: needs Antistasi" };

private _start = (_target getPos [3000, random 360]) vectorAdd [0, 0, 150];
private _spawned = [_side, _faction, ["vehiclesHelisLight", "vehiclesHelisTransport"], _start,
    _start getDir _target, "FLY"] call AID_fnc_spawnVehicle;
if (_spawned isEqualTo []) exitWith {};
_spawned params ["_heli", "_crew"];
_heli flyInHeight 150;
// Recon only: it watches and reports, it never fires.
_crew setCombatMode "BLUE";
_crew setBehaviour "CARELESS";
_crew move getPosATL _target;
diag_log format ["[AI Director] Recon helicopter %1 inbound to %2", typeOf _heli, _playerName];

waitUntil { sleep 2; !alive _heli || { _heli distance2D _target < 600 } };
private _overheadUntil = time + 120;
while { alive _heli && { time < _overheadUntil } } do {
    _crew move getPosATL _target;
    private _seen = allPlayers select { _x distance2D _heli < 800 };
    {
        private _group = _x;
        if (side _group == _side && { _seen findIf { leader _group distance2D _x < 2000 } >= 0 }) then {
            { _group reveal [_x, 2.5] } forEach _seen;
        };
    } forEach allGroups;
    sleep 10;
};

if (!alive _heli) exitWith { diag_log "[AI Director] Recon helicopter lost" };
_crew move (_heli getPos [6000, _target getDir _heli]);
waitUntil { sleep 5; !alive _heli || { allPlayers findIf { _x distance2D _heli < 3000 } < 0 } };
if (alive _heli) then {
    { deleteVehicle _x } forEach units _crew;
    deleteVehicle _heli;
};
diag_log "[AI Director] Recon helicopter gone";
