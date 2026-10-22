/*
    Has the enemy launch a major attack through Antistasi's own attack choice (A3A_fnc_chooseAttack),
    which picks a rebel-held target (possibly the HQ) or a supply convoy, and pays for it from the side's
    attack resources. Scheduled environment only.

    Side: AID_patrolSide if set, otherwise Occupants.
*/
if (isNil "A3A_fnc_chooseAttack") exitWith { diag_log "[AI Director] launch_offensive: Antistasi is not running" };
if (missionNamespace getVariable ["bigAttackInProgress", false]) exitWith {
    diag_log "[AI Director] launch_offensive: a big attack is already in progress"
};
private _side = missionNamespace getVariable ["AID_patrolSide", Occupants];

diag_log format ["[AI Director] Launching %1 offensive", _side];
private _launched = [_side] call A3A_fnc_chooseAttack;
if (!_launched) then { diag_log "[AI Director] launch_offensive: Antistasi found no valid attack" };
