/*
    The player with this name, or objNull (logged with the encounter's name).

    Arguments:
    0: Player name <STRING>
    1: Encounter name, for the log <STRING>

    Returns: <OBJECT>
*/
params ["_playerName", "_encounter"];
private _index = allPlayers findIf { name _x == _playerName };
if (_index < 0) exitWith {
    diag_log format ["[AI Director] %1: no player named %2", _encounter, _playerName];
    objNull
};
allPlayers select _index
