/*
    Antistasi's invader punishment (A3A_fnc_invaderPunish) of a rebel-supporting town: an invader force with
    special forces and air support attacks the town and its civilians after a few minutes' warning, and the
    rebels get a "Defend" task. Always the invaders. Like Antistasi's own punishments (A3A_fnc_chooseAttack) it
    needs punishments enabled and the war level they start at, and costs the invaders 400 attack resources.
    Antistasi only; scheduled.

    Arguments:
    0: Town name as the director knows it <STRING>
*/
params ["_place"];
if (isNil "A3A_fnc_invaderPunish") exitWith { diag_log "[AI Director] punish_town: Antistasi is not running" };
private _outcome = { ["outcome", format ["Your punish_town on %1: %2", _place, _this]] call AID_fnc_event };
if !([] call AID_fnc_punishmentsAllowed) exitWith {
    "not launched, punishments are off in this campaign or the war level is too low" call _outcome
};
if (missionNamespace getVariable ["bigAttackInProgress", false]) exitWith {
    "not launched, a big attack is already in progress" call _outcome
};
([_place, Invaders, "town", [teamPlayer]] call AID_fnc_attackTarget) params ["_marker", "_problem"];
if (_problem != "") exitWith { format ["not launched, %1", _problem] call _outcome };

private _origin = [Invaders, markerPos _marker] call A3A_fnc_availableBasesAir;
diag_log format ["[AI Director] Invader punishment of %1 from %2", _marker, _origin];
[-400, Invaders, "attack"] call A3A_fnc_addEnemyResources;
bigAttackInProgress = true; publicVariable "bigAttackInProgress";
[_marker, _origin] spawn A3A_fnc_invaderPunish;
format ["launched from %1", [_origin] call AID_fnc_placeName] call _outcome;
