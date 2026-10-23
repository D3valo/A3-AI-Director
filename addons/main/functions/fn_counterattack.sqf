/*
    Antistasi's counterattack (A3A_fnc_singleAttack) on a rebel-held location: the mixed ground and air force
    Antistasi sends to retake a place the rebels just captured, sized from the side's defence budget for that
    place (2-6 vehicles) and paid from its defence resources. It ends when the place falls, the force is broken or
    after 45 minutes. Antistasi only; scheduled.

    Arguments:
    0: Location name as the director knows it <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params ["_place", ["_enemy", ""]];
if (isNil "A3A_fnc_singleAttack") exitWith { diag_log "[AI Director] counterattack: Antistasi is not running" };
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;
private _outcome = {
    ["outcome", format ["Your counterattack (%1) on %2: %3", [_side] call AID_fnc_sideName, _place, _this]]
        call AID_fnc_event
};

([_place, _side, "base", [teamPlayer]] call AID_fnc_attackTarget) params ["_marker", "_problem"];
if (_problem != "") exitWith { format ["not launched, %1", _problem] call _outcome };

// Sized as Antistasi sizes its own counterattacks (A3A_fnc_markerChange), but always at least two vehicles.
private _resources = [_side, teamPlayer, _marker] call A3A_fnc_maxDefenceSpend;
private _vehCount = 2 max round (_resources / A3A_balanceVehicleCost) min 6;
private _reveal = [markerPos _marker] call A3A_fnc_calculateSupportCallReveal;
_reveal = [_side, markerPos _marker, _reveal] call A3A_fnc_useRadioKey;

diag_log format ["[AI Director] Counterattack by %1 on %2 with %3 vehicles", _side, _marker, _vehCount];
[[_marker, _side, _vehCount, _reveal], "A3A_fnc_singleAttack"] call A3A_fnc_scheduler;
A3A_supportStrikes pushBack [_side, "TROOPS", markerPos _marker, time + 2700, 2700, _resources];
format ["launched with %1 vehicles", _vehCount] call _outcome;
