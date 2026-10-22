/*
    Starts the director on the server. Settings are mission namespace variables, which can be changed
    at any time from the debug console (server exec):

    AID_enabled      - false stops sending states and running decisions (the off switch).
    AID_mode         - "propose": decisions are announced and wait for [] call AID_fnc_approve;
                       "auto": decisions run at once.
    AID_interval     - seconds between game states sent to the companion.
    AID_request      - a wish for the director in plain words, e.g. "send a patrol at us". Sent at once,
                       then cleared; the director carries it out when its cooldowns allow.
    AID_patrolSide   - side of spawned patrols. Unset by default: patrols then use Antistasi's Occupants
                       (looked up when each patrol spawns, as Antistasi sets it after this runs), or east.
    AID_patrolUnits  - unit classes for patrols outside Antistasi, used in order and repeated as needed.
    AID_chatUIDs     - Steam UIDs (strings) allowed to use the chat commands besides the host and admins.
    AID_maxDirectorUnits - the most director-spawned soldiers alive at once; patrols beyond it are refused.
    AID_protectHQ    - "director" (default): the director never attacks the rebel HQ (no offensives on it, no
                       encounters against players within AID_hqRadius of it); "all": Antistasi's own attacks on
                       the HQ are stopped too; "off": no protection.
    AID_hqRadius     - metres around the HQ that count as at the HQ (default 500).
    AID_personality  - the director's style for this session (a built-in or custom style); "" uses the
                       campaign's.
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
    ["AID_patrolUnits", ["O_Soldier_TL_F", "O_Soldier_AR_F", "O_Soldier_GL_F", "O_Soldier_LAT_F"]],
    ["AID_chatUIDs", []],
    ["AID_maxDirectorUnits", 24],
    ["AID_personality", ""],
    ["AID_protectHQ", "director"],
    ["AID_hqRadius", 500]
];
AID_pending = nil;
AID_spawnedGroups = [];

addMissionEventHandler ["ExtensionCallback", { _this call AID_fnc_onCallback }];
call AID_fnc_initChat;
[] spawn AID_fnc_loop;
[] spawn AID_fnc_protectHQ;
