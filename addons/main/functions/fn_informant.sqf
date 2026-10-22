/*
    A civilian informant appears 150-250 m from the named player, out of sight, and walks to them. When a player
    reaches them, they say their piece (the director's line, or a default) and the enemy groups near that player
    are marked on the map as with reveal_enemies; then they walk off and are removed. Gives up after 10 minutes.
    Uses the Antistasi civilian template where there is one. Scheduled.

    Arguments:
    0: Player name <STRING>
    1: What the informant says, or "" <STRING>
*/
params ["_playerName", ["_message", ""]];

private _target = [_playerName, "informant"] call AID_fnc_findPlayer;
if (isNull _target) exitWith {};
private _pos = [_target, 150, 250] call AID_fnc_findSpawnPos;
if (_pos isEqualTo []) exitWith { diag_log "[AI Director] informant: no hidden position found" };

private _group = createGroup [civilian, true];
private _informant = if (isNil "A3A_faction_civ") then {
    _group createUnit ["C_man_1", _pos, [], 0, "NONE"]
} else {
    [_group, A3A_faction_civ get "unitMan", _pos, [], 0, "NONE"] call A3A_fnc_createUnit
};
AID_lastInformant = _informant;  // for the self-test
_informant allowFleeing 0;
_group setBehaviour "CARELESS";
_group setSpeedMode "FULL";
diag_log format ["[AI Director] Informant walking to %1 from %2 m", _playerName, round (_pos distance2D _target)];

private _deadline = time + 600;
private _reached = objNull;
while { alive _informant && { time < _deadline } && { isNull _reached } } do {
    private _index = allPlayers findIf { alive _x && { _x distance _informant < 5 } };
    if (_index >= 0) then {
        _reached = allPlayers select _index;
    } else {
        // Follow the player they were sent to, or whoever is now closest.
        private _goal = [_target, allPlayers param [0, objNull]] select (!alive _target);
        if (!isNull _goal) then { _informant doMove getPosATL _goal };
        sleep 3;
    };
};

if (!isNull _reached) then {
    _informant doWatch _reached;
    private _line = [_message, "They're closer than you think. I've marked what I saw on your map."] select (_message == "");
    [format ["Informant: %1", _line]] remoteExec ["hint", allPlayers select { _x distance _reached < 30 }];
    [name _reached] spawn AID_fnc_revealEnemies;
    ["outcome", format ["Your informant reached %1 and marked the enemies near them", name _reached]]
        call AID_fnc_event;
    sleep 5;
    _informant doMove (_informant getPos [400, _reached getDir _informant]);
    sleep 120;
} else {
    ["outcome", ["Your informant was killed before reaching anyone", "Your informant never reached anyone"]
        select (alive _informant)] call AID_fnc_event;
};
deleteVehicle _informant;
