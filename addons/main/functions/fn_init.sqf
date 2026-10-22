/*
    Starts the director on the server. Settings are mission namespace variables, which can be changed
    at any time from the debug console (server exec):

    AID_enabled      - false stops sending states and running decisions (the off switch).
    AID_mode         - "propose": decisions are announced and wait for [] call AID_fnc_approve;
                       "auto": decisions run at once.
    AID_interval     - seconds between game states sent to the companion.
    AID_request      - a wish for the director in plain words, e.g. "send a patrol at us". Sent at once,
                       then cleared; the director carries it out when its cooldowns allow.
    AID_patrolSide   - side of spawned patrols.
    AID_patrolUnits  - unit classes for spawned patrols, used in order and repeated as needed.
*/
if (!isServer) exitWith {};

private _version = "ai_director" callExtension ["version", []];
if (_version select 1 != 0 || {_version select 0 == ""}) exitWith {
    diag_log format ["[AI Director] Extension ai_director_x64.dll not loaded (%1); director disabled.", _version];
};
diag_log format ["[AI Director] Extension %1 loaded.", _version select 0];

{
    if (isNil _x) then { missionNamespace setVariable [_x, _y]; };
} forEach createHashMapFromArray [
    ["AID_enabled", true],
    ["AID_mode", "propose"],
    ["AID_interval", 90],
    ["AID_request", ""],
    ["AID_patrolSide", missionNamespace getVariable ["Occupants", east]],
    ["AID_patrolUnits", ["O_Soldier_TL_F", "O_Soldier_AR_F", "O_Soldier_GL_F", "O_Soldier_LAT_F"]]
];
AID_pending = nil;

addMissionEventHandler ["ExtensionCallback", { _this call AID_fnc_onCallback }];
[] spawn AID_fnc_loop;
