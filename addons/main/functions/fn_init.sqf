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
    AID_arcRequest   - ["start", idea] or ["stop", ""]: asks the companion to plan or stop a story arc (set
                       by !director arc). Sent at once, then cleared.
    AID_personality  - the director's style for this session (a built-in or custom style); "" uses the
                       campaign's.
    AID_cooldowns    - false lets the director use any action at any time (!director cooldowns off); the companion
                       enforces the cooldowns and reads this from each state.
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
    ["AID_hqRadius", 500],
    ["AID_cooldowns", true]
];
// Antistasi Ultimate's random events by the director's names: [function, the flag Antistasi runs it under].
AID_antistasiEvents = createHashMapFromArray [
    ["civilian_heli", ["SCRT_fnc_encounter_civHeli", "isEventInProgress"]],
    ["civilian_plane", ["SCRT_fnc_encounter_civPlane", "isEventInProgress"]],
    ["police_patrol", ["SCRT_fnc_encounter_police", "isEventInProgress"]],
    ["police_skirmish", ["SCRT_fnc_encounter_policeSkirmish", "isEventInProgress"]],
    ["police_hostages", ["SCRT_fnc_encounter_policeHostages", "isEventInProgress"]],
    ["supply_truck", ["SCRT_fnc_encounter_vehicleMove", "isEventInProgress"]],
    ["outpost_patrol", ["SCRT_fnc_encounter_vehiclePatrol", "isEventInProgress"]],
    ["ambush_wreck", ["SCRT_fnc_encounter_postAmbush", "isEventInProgress"]],
    ["ambushed_convoy", ["SCRT_fnc_encounter_postAmbushConvoy", "isEventInProgress"]],
    ["battle_aftermath", ["SCRT_fnc_encounter_postBattle", "isEventInProgress"]],
    ["repair_crew", ["SCRT_fnc_encounter_repair", "isEventInProgress"]],
    ["medevac", ["SCRT_fnc_encounter_MedEvac", "isEventInProgress"]],
    ["heli_slingload", ["SCRT_fnc_encounter_HeliSlingloadCargo", "isEventInProgress"]],
    ["frontline_skirmish", ["SCRT_fnc_encounter_frontlineSkirmish", "isEventInProgress"]],
    ["specops_airdrop", ["SCRT_fnc_encounter_SpecOpsAirdrop", "isEventInProgress"]],
    ["rivals_car_bomb", ["SCRT_fnc_rivals_encounter_carDemo", "isRivalEventInProgress"]],
    ["rivals_drone_strike", ["SCRT_fnc_rivals_encounter_uavFlyby", "isRivalEventInProgress"]],
    ["rivals_roving_mortar", ["SCRT_fnc_rivals_encounter_rovingMortar", "isRivalEventInProgress"]],
    ["rivals_heli_raid", ["SCRT_fnc_rivals_encounter_heliRaid", "isRivalEventInProgress"]],
    // These two clear isEventInProgress when they end (see AID_fnc_antistasiEvent).
    ["rivals_vs_occupants", ["SCRT_fnc_rivals_encounter_OccVsRivalsSkirmish", "isEventInProgress"]],
    ["rivals_vs_police", ["SCRT_fnc_rivals_encounter_policeVsRivalsskirmish", "isEventInProgress"]]
];
// Kinds of location Antistasi's own attacks go for (A3A_fnc_findAttackTargets), besides towns and the HQ.
AID_attackableKinds = ["airbase", "military base", "outpost", "seaport", "factory", "resource"];
// Antistasi's support types by the director's names (see A3A_fnc_initSupports).
AID_supportTypes = createHashMapFromArray [
    ["airstrike", "AIRSTRIKE"], ["carpet_bombs", "CARPETBOMBS"], ["cruise_missile", "CRUISEMISSILE"],
    ["orbital_strike", "ORBITALSTRIKE"], ["gunship", "GUNSHIP"], ["artillery", "ARTILLERY"], ["mortar", "MORTAR"],
    ["howitzer", "HOWITZER"], ["cas", "CAS"], ["cas_dive", "CASDIVE"], ["uav_attack", "UAVAttack"], ["tank", "TANK"],
    ["qrf_land", "QRFLAND"], ["qrf_air", "QRFAIR"], ["qrf_vehicle_airdrop", "QRFVEHAIRDROP"],
    ["qrf_orbital", "QRFORBITAL"], ["air_superiority", "ASF"], ["sam", "SAM"]
];
AID_pending = nil;
AID_arcRequest = [];
AID_arcStatus = "";  // the running arc, as last reported by the companion
AID_arcOwner = 2;    // who asked for it: arc news goes to them only
AID_requestOwner = 2;  // who sent the pending request: news of it goes to them
AID_notes = [];        // standing facts from the host (!director note), at most 5
AID_spawnedGroups = [];

addMissionEventHandler ["ExtensionCallback", { _this call AID_fnc_onCallback }];
call AID_fnc_initFeedback;
call AID_fnc_initChat;
[] spawn AID_fnc_loop;
[] spawn AID_fnc_protectHQ;
