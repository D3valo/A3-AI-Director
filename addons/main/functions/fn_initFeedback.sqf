/*
    Sets up the director's feedback: what happened since the last state, sent with the next one (see
    AID_fnc_feedback). Server only; called once by AID_fnc_init.

    AID_events      - queued events: hashmaps of id, time (game seconds), kind and text. Kinds: "kills" (tallies),
                      "player", "location", "attack", "mission", "outcome" (of the director's own actions) and
                      "proposal". Removed once a state carrying them has been sent; at most 50 are kept.
    AID_encounters  - the director's encounters still under way (see AID_fnc_trackEncounter).
    AID_killCounts  - kills since the last state, by "victims|killers" side names.
*/
AID_events = [];
AID_eventSeq = 0;
AID_encounters = [];
AID_encounterSeq = 0;
AID_killCounts = createHashMap;
// [time, "taken" | "lost" | "kills" | "losses", count] for the rebels' momentum over the last 30 minutes.
AID_momentum = [];

addMissionEventHandler ["EntityKilled", {
    params ["_victim", "_killer", "_instigator"];
    if !(_victim isKindOf "CAManBase") exitWith {};
    private _shooter = [_killer, _instigator] select !isNull _instigator;
    if (isPlayer _victim) then {
        private _how = if (isNull _shooter || { _shooter == _victim }) then {
            "died (bled out, fell or crashed; no one to credit)"
        } else {
            format ["was killed by the %1", [side group _shooter] call AID_fnc_sideName]
        };
        ["player", format ["%1 %2", name _victim, _how]] call AID_fnc_event;
    };
    if (isNull _shooter || { _shooter == _victim }) exitWith {};
    private _victims = [_victim getVariable ["originalSide", side group _victim]] call AID_fnc_sideName;
    private _killers = [side group _shooter] call AID_fnc_sideName;
    if (_victims == _killers || { _victims == "" } || { _killers == "" }) exitWith {};
    private _key = format ["%1|%2", _victims, _killers];
    AID_killCounts set [_key, (AID_killCounts getOrDefault [_key, 0]) + 1];
}];
