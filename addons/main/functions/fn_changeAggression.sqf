/*
    Raises or lowers an enemy side's aggression through Antistasi (A3A_fnc_addAggression), which makes it react
    harder or softer: more or fewer attacks, supports and patrols. The change fades over its duration, as
    Antistasi's own aggression does. Antistasi only.

    Arguments:
    0: Enemy side: "occupants", "invaders" or "" for the default <STRING>
    1: Points to add (negative lowers it) <NUMBER>
    2: Minutes the change lasts <NUMBER> (default 30)
    3: Who asked, for the event: "director" or "host" <STRING> (default "director")
*/
params [["_enemy", ""], "_points", ["_minutes", 30], ["_by", "director"]];
if (isNil "A3A_fnc_addAggression") exitWith { diag_log "[AI Director] change_aggression: needs Antistasi" };
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;
private _var = ["aggressionInvaders", "aggressionOccupants"] select (_side == Occupants);
private _before = missionNamespace getVariable [_var, 0];
// Not scaled down for small player counts: the change is meant as given.
[_side, _points, _minutes, true] call A3A_fnc_addAggression;
// Antistasi recalculates the aggression value on its own schedule, so only the change and the old value are known.
[["outcome", "host"] select (_by == "host"), format ["%1 the %2's aggression by %3 for %4 min (it was %5)",
    ["Your change_aggression changed", "The host changed"] select (_by == "host"), [_side] call AID_fnc_sideName,
    _points, _minutes, round _before]] call AID_fnc_event;
