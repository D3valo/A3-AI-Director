/*
    Brings the director's feedback up to date before a state is gathered: turns the kill tallies into events,
    notices what changed since the last call (players down, back up or respawned, the rebel HQ under attack,
    locations changing hands, big attacks, missions with their titles and results), and follows the director's
    encounters (contact, and an event when one ends). Server only, from AID_fnc_loop.
*/

// Kill tallies since the last call. Heavy fighting (5 or more killed, or 3 or more rebels) is kind "battle", which
// the companion treats as news; lighter tallies are "kills".
private _singular = createHashMapFromArray [["rebels", "rebel"], ["occupants", "occupant"], ["invaders", "invader"], ["civilians", "civilian"]];
{
    (_x splitString "|") params ["_victims", "_killers"];
    private _heavy = _y >= 5 || { _victims == "rebels" && { _y >= 3 } };
    if (_killers == "rebels" && { _victims in ["occupants", "invaders"] }) then { AID_momentum pushBack [time, "kills", _y] };
    if (_victims == "rebels" && { _killers in ["occupants", "invaders"] }) then { AID_momentum pushBack [time, "losses", _y] };
    [["kills", "battle"] select _heavy, format ["The %1 killed %2 %3", _killers, _y,
        [_victims, _singular getOrDefault [_victims, _victims]] select (_y == 1)]] call AID_fnc_event;
} forEach AID_killCounts;
AID_killCounts = createHashMap;
// Keep the last 30 minutes of momentum (see AID_fnc_gatherState).
AID_momentum = AID_momentum select { (_x select 0) > time - 1800 };

// Players down, back up, or respawned (a respawn is a new unit for the same player).
private _lastPlayers = missionNamespace getVariable ["AID_lastPlayers", createHashMap];
private _players = createHashMap;
{
    private _uid = getPlayerUID _x;
    private _now = lifeState _x;
    (_lastPlayers getOrDefault [_uid, [_x, _now]]) params ["_unitBefore", "_before"];
    private _respawned = _unitBefore isNotEqualTo _x;
    switch (true) do {
        case (_respawned): {
            private _where = ["", " at the HQ"] select ("Synd_HQ" in allMapMarkers && { _x distance2D markerPos "Synd_HQ" < AID_hqRadius });
            ["player", format ["%1 respawned%2", name _x, _where]] call AID_fnc_event;
        };
        case (_now == "INCAPACITATED" && { _before != "INCAPACITATED" }): {
            ["player", format ["%1 is down", name _x]] call AID_fnc_event;
        };
        case (_before == "INCAPACITATED" && { _now in ["HEALTHY", "INJURED"] }): {
            ["player", format ["%1 is back up", name _x]] call AID_fnc_event;
        };
    };
    _players set [_uid, [_x, _now]];
} forEach allPlayers;
AID_lastPlayers = _players;

// The rebel HQ under attack: 4 or more hostile soldiers within AID_hqRadius, and when that ends.
if ("Synd_HQ" in allMapMarkers) then {
    private _rebels = missionNamespace getVariable ["teamPlayer", independent];
    private _hostile = { alive _x && { [_rebels, side group _x] call BIS_fnc_sideIsEnemy } && { side group _x != civilian } }
        count (markerPos "Synd_HQ" nearEntities ["CAManBase", AID_hqRadius]);
    private _attacked = missionNamespace getVariable ["AID_hqAttacked", false];
    if (_hostile >= 4 && { !_attacked }) then {
        ["attack", format ["The rebel HQ is under attack: %1 enemies within %2 m", _hostile, AID_hqRadius]] call AID_fnc_event;
        AID_hqAttacked = true;
    };
    if (_hostile == 0 && { _attacked }) then {
        ["attack", "No enemies are left at the rebel HQ"] call AID_fnc_event;
        AID_hqAttacked = false;
    };
};

// Antistasi: locations changing hands, big attacks, missions.
if (!isNil "markersX" && { !isNil "sidesX" }) then {
    private _owners = createHashMap;
    { _owners set [_x, [sidesX getVariable [_x, sideUnknown]] call AID_fnc_sideName] } forEach (markersX + citiesX - ["Synd_HQ"]);
    private _before = missionNamespace getVariable ["AID_lastOwners", _owners];
    {
        private _was = _before getOrDefault [_x, _y];
        if (_was != _y && { _y != "" }) then {
            ["location", format ["%1 was taken by the %2 (from the %3)", [_x] call AID_fnc_placeName, _y, _was]] call AID_fnc_event;
            if (_y == "rebels") then { AID_momentum pushBack [time, "taken", 1] };
            if (_was == "rebels") then { AID_momentum pushBack [time, "lost", 1] };
        };
    } forEach _owners;
    AID_lastOwners = _owners;

    private _attack = missionNamespace getVariable ["bigAttackInProgress", false];
    private _attackBefore = missionNamespace getVariable ["AID_lastBigAttack", _attack];
    if (_attack && { !_attackBefore }) then { ["attack", "A major enemy attack has begun"] call AID_fnc_event };
    if (!_attack && { _attackBefore }) then { ["attack", "The major enemy attack is over"] call AID_fnc_event };
    AID_lastBigAttack = _attack;

    // Missions by task: [id, type, state, created]; the state moves to SUCCEEDED or FAILED before deletion.
    private _title = {
        params ["_id", "_type"];
        private _description = _id call BIS_fnc_taskDescription;
        private _text = (_description param [1, [""]]) param [0, ""];
        [format ["%1 (%2)", _text, _type], _type] select (_text == "")
    };
    private _tasks = createHashMap;
    { _tasks set [_x select 0, [_x select 1, _x select 2]] } forEach (missionNamespace getVariable ["A3A_tasksData", []]);
    private _tasksBefore = missionNamespace getVariable ["AID_lastTasks", _tasks];
    {
        _y params ["_type", "_state"];
        private _old = _tasksBefore getOrDefault [_x, []];
        if (_old isEqualTo []) then {
            ["mission", format ["Mission started: %1", [_x, _type] call _title]] call AID_fnc_event;
        } else {
            if (_state != (_old select 1) && { _state in ["SUCCEEDED", "FAILED"] }) then {
                ["mission", format ["Mission %1: %2", toLower _state, [_x, _type] call _title]] call AID_fnc_event;
            };
        };
    } forEach _tasks;
    {
        if !(_x in _tasks) then { ["mission", format ["Mission closed: %1", _y select 0]] call AID_fnc_event };
    } forEach _tasksBefore;
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
