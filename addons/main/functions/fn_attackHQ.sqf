/*
    Antistasi's assault on the rebel HQ (A3A_fnc_attackHQ): a UAV, then a special forces air assault to kill
    Petros, with a "Defend" task for the rebels. Only with AID_protectHQ "off". Like Antistasi's own HQ attacks
    (A3A_fnc_chooseAttack) it costs the side 400 attack resources, and the force is paid from attack resources.
    Antistasi only; scheduled.

    Arguments:
    0: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params [["_enemy", ""]];
if (isNil "A3A_fnc_attackHQ") exitWith { diag_log "[AI Director] attack_hq: Antistasi is not running" };
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;
private _outcome = {
    ["outcome", format ["Your attack_hq (%1): %2", [_side] call AID_fnc_sideName, _this]] call AID_fnc_event
};
if (AID_protectHQ != "off") exitWith { "not launched, the HQ is protected" call _outcome };
if (missionNamespace getVariable ["bigAttackInProgress", false]) exitWith {
    "not launched, a big attack is already in progress" call _outcome
};
if !("Synd_HQ" in allMapMarkers) exitWith { "not launched, the rebels have no HQ" call _outcome };

private _origin = [_side, markerPos "Synd_HQ"] call A3A_fnc_availableBasesAir;
diag_log format ["[AI Director] HQ attack by %1 from %2", _side, _origin];
[-400, _side, "attack"] call A3A_fnc_addEnemyResources;
bigAttackInProgress = true; publicVariable "bigAttackInProgress";
HQAttackInProgress = true; publicVariable "HQAttackInProgress";
[_side, _origin] spawn A3A_fnc_attackHQ;
format ["launched from %1", [_origin] call AID_fnc_placeName] call _outcome;
