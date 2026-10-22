/*
    Spawns enemy infantry from Antistasi unit types the way Antistasi spawns its own: A3A_fnc_spawnGroup, units
    initialised for the attack pool and 10 attack resources charged per soldier, the group tracked for the
    soldier cap. Antistasi only; scheduled.

    Arguments:
    0: Side <SIDE>
    1: Unit types (Antistasi loadout names) <ARRAY>
    2: Position ATL <ARRAY>

    Returns: <GROUP>
*/
params ["_side", "_types", "_pos"];
private _group = [_pos, _side, _types] call A3A_fnc_spawnGroup;
{ [_x, "", false, "attack"] call A3A_fnc_NATOinit } forEach units _group;
[-10 * count units _group, _side, "attack"] call A3A_fnc_addEnemyResources;
AID_spawnedGroups pushBack _group;
_group
