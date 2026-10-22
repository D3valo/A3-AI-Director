/*
    Spawns a rebel group from the rebels' Antistasi template, set up like Antistasi's own recruits (FIAinit), and
    hands it to a player: under the rebel commander's high command if that player is the commander, else into
    the player's own group. A gift from the director: it costs the rebels nothing. Antistasi only; scheduled.

    Arguments:
    0: Player who gets the group <OBJECT>
    1: Strength, "fireteam" (groupMedium, 4) or "squad" (groupSquad) <STRING>
    2: Position ATL <ARRAY>
    3: Group name prefix <STRING>

    Returns: <GROUP> the spawned group (empty if the soldiers joined the player's group)
*/
params ["_player", "_strength", "_pos", "_name"];
private _types = A3A_faction_reb get (["groupMedium", "groupSquad"] select (_strength == "squad"));
private _group = [_pos, teamPlayer, _types, true] call A3A_fnc_spawnGroup;
{ [_x] call A3A_fnc_FIAinit } forEach units _group;
if (_player isEqualTo (missionNamespace getVariable ["theBoss", objNull])) then {
    _group setGroupIdGlobal [format ["%1 %2", _name, round random 99]];
    _player hcSetGroup [_group];
} else {
    units _group joinSilent group _player;
};
_group
