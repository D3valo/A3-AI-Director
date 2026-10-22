/*
    Whether the director may spawn this many more soldiers under AID_maxDirectorUnits. Logs a refusal.

    Arguments:
    0: Soldiers about to spawn <NUMBER>
    1: Encounter name, for the log <STRING>

    Returns: <BOOL>
*/
params ["_count", "_encounter"];
private _alive = [] call AID_fnc_directorUnits;
if (_alive + _count > AID_maxDirectorUnits) exitWith {
    diag_log format ["[AI Director] %1: %2 director soldiers alive, cap %3", _encounter, _alive, AID_maxDirectorUnits];
    false
};
true
