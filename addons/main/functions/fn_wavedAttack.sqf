/*
    Antistasi's major attack (A3A_fnc_wavedAttack) on a named location held by the rebels or by the other enemy:
    one to three waves of ground and air forces from the attacking side's air base, with a "Defend" task for the
    rebels. Like Antistasi's own major attacks (A3A_fnc_chooseAttack) it costs the side 400 attack resources up
    front, and the waves are paid from attack resources as they spawn. Antistasi only; scheduled.

    Arguments:
    0: Location name as the director knows it <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
    2: Waves, 1-3 <NUMBER>
*/
params ["_place", ["_enemy", ""], ["_waves", 2]];
if (isNil "A3A_fnc_wavedAttack") exitWith { diag_log "[AI Director] waved_attack: Antistasi is not running" };
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;
_waves = 1 max round _waves min 3;
private _outcome = {
    ["outcome", format ["Your waved_attack (%1) on %2: %3", [_side] call AID_fnc_sideName, _place, _this]]
        call AID_fnc_event
};
if (missionNamespace getVariable ["bigAttackInProgress", false]) exitWith {
    "not launched, a big attack is already in progress" call _outcome
};
private _otherEnemy = [Occupants, Invaders] select (_side == Occupants);
([_place, _side, "base", [teamPlayer, _otherEnemy]] call AID_fnc_attackTarget) params ["_marker", "_problem"];
if (_problem != "") exitWith { format ["not launched, %1", _problem] call _outcome };

private _origin = [_side, markerPos _marker] call A3A_fnc_availableBasesAir;
diag_log format ["[AI Director] Waved attack by %1 on %2 from %3, %4 waves", _side, _marker, _origin, _waves];
[-400, _side, "attack"] call A3A_fnc_addEnemyResources;
bigAttackInProgress = true; publicVariable "bigAttackInProgress";
[_marker, _origin, _waves] spawn A3A_fnc_wavedAttack;
format ["launched, %1 waves from %2", _waves, [_origin] call AID_fnc_placeName] call _outcome;
