/*
    Starts tracking an encounter the director spawned, so the director hears how it goes: soldiers alive and
    killed, when it made contact, and how it ended (see AID_fnc_feedback).

    Arguments:
    0: Action, e.g. "spawn_patrol" <STRING>
    1: Side <SIDE>
    2: Target player's name <STRING>
    3: Groups <ARRAY>

    Returns: <HASHMAP> the encounter's record; set "note" on it to add what else happened
*/
params ["_action", "_side", "_target", "_groups"];
AID_encounterSeq = AID_encounterSeq + 1;
private _units = [];
{ _units append units _x } forEach _groups;
private _record = createHashMapFromArray [
    ["id", AID_encounterSeq], ["action", _action], ["side", [_side] call AID_fnc_sideName], ["target", _target],
    ["started", time], ["units", _units], ["contact", -1], ["note", ""]
];
AID_encounters pushBack _record;
_record
