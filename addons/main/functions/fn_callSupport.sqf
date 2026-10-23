/*
    Has Antistasi's enemy react to the named player as if one of its units had spotted them and called for
    support. Scheduled environment only.

    Without a support type, Antistasi's own support logic (A3A_fnc_requestSupport) picks a QRF, artillery, air
    support or nothing, from the side's defence resources and its checks for friendlies and civilians nearby.
    With one, that support is sent (A3A_fnc_createSupport) if Antistasi would allow it: the faction has it, its
    availability check passes (war level, target type), the side's defence budget for the area allows a spend,
    and an area strike wouldn't hit more than two of the side's own soldiers.

    Arguments:
    0: Player name <STRING>
    1: Enemy side: "occupants", "invaders" or "" for the default (see AID_fnc_enemyFaction) <STRING>
    2: Support type as the director names it (see AID_supportTypes), or "" for Antistasi's choice <STRING>
*/
params ["_playerName", ["_enemy", ""], ["_supportType", ""]];

if (isNil "A3A_fnc_requestSupport") exitWith { diag_log "[AI Director] call_support: Antistasi is not running" };
private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] call_support: no player named %1", _playerName] };
_target = allPlayers select _target;
private _side = ([_enemy] call AID_fnc_enemyFaction) select 0;
private _sideName = [_side] call AID_fnc_sideName;

if (_supportType != "") exitWith {
    private _outcome = {
        ["outcome", format ["Your call_support %1 (%2) against %3: %4", _supportType, _sideName, _playerName, _this]]
            call AID_fnc_event
    };
    private _a3aType = AID_supportTypes getOrDefault [_supportType, ""];
    private _types = [A3A_supportTypesOcc, A3A_supportTypesInv] select (_side == Invaders);
    if !(_a3aType in _types) exitWith { "not sent, the faction has no such support" call _outcome };
    // Supports aim at the vehicle a player is in, as Antistasi's own calls do.
    private _supportTarget = [_target, objectParent _target] select !isNull objectParent _target;
    private _targPos = _supportTarget getPos [random 40, random 360];
    private _available = [_supportTarget, _side, 0, keys _types]
        call (missionNamespace getVariable format ["A3A_fnc_SUP_%1Available", _a3aType]);
    if (_available <= 0) exitWith {
        "not sent, Antistasi doesn't allow it against this target now (war level or target type)" call _outcome
    };
    private _maxSpend = [_side, _supportTarget, getPosATL _target] call A3A_fnc_maxDefenceSpend;
    if (_maxSpend <= 0) exitWith { "not sent, the side's defence budget for this area is spent" call _outcome };
    private _radius = (_types get _a3aType) select 2;
    if (_radius > 0 && { count (units _side inAreaArray [_targPos, _radius, _radius]) > 2 }) exitWith {
        "not sent, the side's own soldiers are too close to the target" call _outcome
    };

    diag_log format ["[AI Director] Sending %1 %2 support against %3", _side, _a3aType, _playerName];
    // Reveal 0.5: players may hear the call.
    private _name = [_a3aType, _side, getPosATL _target, _maxSpend, _supportTarget, _targPos, 0.5]
        call A3A_fnc_createSupport;
    (["sent", "not sent, Antistasi couldn't create it (nothing in range or no vehicle free)"] select (_name == ""))
        call _outcome;
};

diag_log format ["[AI Director] Requesting %1 support against %2 at %3", _side, _playerName, getPosATL _target];
private _strikesBefore = +(missionNamespace getVariable ["A3A_supportStrikes", []]);
private _activeBefore = +(missionNamespace getVariable ["A3A_activeSupports", []]);
// Precision 3 of 4: the spotter knows roughly where they are. Reveal 0.5: players may hear the call.
[_side, _target, getPosATL _target, 3, 0.5] call A3A_fnc_requestSupport;

// What Antistasi sent: a new active support (by type) or a new strike (by class), or nothing.
private _types = ((missionNamespace getVariable ["A3A_activeSupports", []]) select { !(_x in _activeBefore) })
    apply { _x select 2 };
private _classes = ((missionNamespace getVariable ["A3A_supportStrikes", []]) select { !(_x in _strikesBefore) })
    apply { _x select 1 };
private _sent = [_types, _classes] select (_types isEqualTo []);
["outcome", [
    format ["Your call_support (%1) against %2: Antistasi sent nothing (no affordable or safe support)",
        _sideName, _playerName],
    format ["Your call_support (%1) against %2: Antistasi sent %3", _sideName, _playerName,
        _sent joinString ", "]
] select (_sent isNotEqualTo [])] call AID_fnc_event;
