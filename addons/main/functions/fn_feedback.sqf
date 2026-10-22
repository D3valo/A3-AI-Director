/*
    Brings the director's feedback up to date before a state is gathered: turns the kill tallies into events,
    notices what changed since the last call (players downed or back up, locations changing hands, big attacks
    starting or ending, missions starting or ending), and follows the director's encounters (contact, and an
    event when one ends). Server only, from AID_fnc_loop.
*/

// Kill tallies since the last call.
{
    (_x splitString "|") params ["_victims", "_killers"];
    ["kills", format ["The %1 killed %2 %3", _killers, _y, _victims]] call AID_fnc_event;
} forEach AID_killCounts;
AID_killCounts = createHashMap;

// Players downed or back up.
private _lifeStates = missionNamespace getVariable ["AID_lastLifeStates", createHashMap];
{
    private _now = lifeState _x;
    private _before = _lifeStates getOrDefault [getPlayerUID _x, _now];
    if (_now == "INCAPACITATED" && { _before != "INCAPACITATED" }) then {
        ["player", format ["%1 is down", name _x]] call AID_fnc_event;
    };
    if (_before == "INCAPACITATED" && { _now in ["HEALTHY", "INJURED"] }) then {
        ["player", format ["%1 is back up", name _x]] call AID_fnc_event;
    };
    _lifeStates set [getPlayerUID _x, _now];
} forEach allPlayers;
AID_lastLifeStates = _lifeStates;

// Antistasi: locations changing hands, big attacks, missions.
if (!isNil "markersX" && { !isNil "sidesX" }) then {
    private _owners = createHashMap;
    { _owners set [_x, [sidesX getVariable [_x, sideUnknown]] call AID_fnc_sideName] } forEach (markersX + citiesX - ["Synd_HQ"]);
    private _before = missionNamespace getVariable ["AID_lastOwners", _owners];
    {
        private _was = _before getOrDefault [_x, _y];
        if (_was != _y && { _y != "" }) then {
            private _name = [_x, [_x] call A3A_fnc_localizar] select (!isNil "A3A_fnc_localizar");
            ["location", format ["%1 was taken by the %2 (from the %3)", _name, _y, _was]] call AID_fnc_event;
        };
    } forEach _owners;
    AID_lastOwners = _owners;

    private _attack = missionNamespace getVariable ["bigAttackInProgress", false];
    private _attackBefore = missionNamespace getVariable ["AID_lastBigAttack", _attack];
    if (_attack && { !_attackBefore }) then { ["attack", "A major enemy attack has begun"] call AID_fnc_event };
    if (!_attack && { _attackBefore }) then { ["attack", "The major enemy attack is over"] call AID_fnc_event };
    AID_lastBigAttack = _attack;

    private _tasks = +(missionNamespace getVariable ["A3A_activeTasks", []]);
    private _tasksBefore = missionNamespace getVariable ["AID_lastTasks", _tasks];
    { ["mission", format ["Mission started: %1", _x]] call AID_fnc_event } forEach (_tasks - _tasksBefore);
    { ["mission", format ["Mission ended: %1", _x]] call AID_fnc_event } forEach (_tasksBefore - _tasks);
    AID_lastTasks = _tasks;
};

// The director's encounters: contact, and an event when one is over.
{
    private _units = _x get "units";
    private _alive = _units select { alive _x };
    if ((_x get "contact") < 0 && { _alive findIf { behaviour _x == "COMBAT" } >= 0 }) then {
        _x set ["contact", time];
    };
    if (_alive isEqualTo []) then {
        private _killed = { !isNull _x } count _units;
        private _how = switch (true) do {
            case (_killed == count _units): { format ["wiped out, all %1 killed", _killed] };
            case (_killed > 0): { format ["over: %1 of %2 killed, the rest despawned", _killed, count _units] };
            default { "over: despawned with no rebels near" };
        };
        private _contact = _x get "contact";
        ["outcome", format ["Your %1 (%2) against %3, %4 min ago: %5%6%7",
            _x get "action", _x get "side", _x get "target", round ((time - (_x get "started")) / 60), _how,
            ["", format [", contact after %1 min", round ((_contact - (_x get "started")) / 60)]] select (_contact >= 0),
            ["", format [". %1", _x get "note"]] select ((_x get "note") != "")
        ]] call AID_fnc_event;
    };
} forEach AID_encounters;
AID_encounters = AID_encounters select { (_x get "units") findIf { alive _x } >= 0 };
