/*
    Has the enemy launch a major attack through Antistasi's own attack choice (A3A_fnc_chooseAttack),
    which picks a rebel-held target or a supply convoy, and pays for it from the side's attack resources. The
    rebel HQ is a possible target only with AID_protectHQ "off". Scheduled environment only.

    Arguments:
    0: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
*/
params [["_enemy", ""]];
if (isNil "A3A_fnc_chooseAttack") exitWith { diag_log "[AI Director] launch_offensive: Antistasi is not running" };
if (missionNamespace getVariable ["bigAttackInProgress", false]) exitWith {
    diag_log "[AI Director] launch_offensive: a big attack is already in progress"
};
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;

// Antistasi only considers the rebel HQ as a target once the side's HQ knowledge reaches 1. While the HQ is
// protected, hold it just below that for this attack choice, then restore it with anything learnt meanwhile.
private _knowledgeVar = ["A3A_curHQInfoInv", "A3A_curHQInfoOcc"] select (_side == Occupants);
private _knowledge = missionNamespace getVariable [_knowledgeVar, 0];
private _held = AID_protectHQ != "off" && { _knowledge >= 1 };
if (_held) then { missionNamespace setVariable [_knowledgeVar, 0.99] };

diag_log format ["[AI Director] Launching %1 offensive%2", _side, ["", " (HQ protected)"] select _held];
private _launched = [_side] call A3A_fnc_chooseAttack;
if (_held) then {
    missionNamespace setVariable [_knowledgeVar, _knowledge + (missionNamespace getVariable [_knowledgeVar, 0.99]) - 0.99];
};
if (!_launched) then { diag_log "[AI Director] launch_offensive: Antistasi found no valid attack" };
