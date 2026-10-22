/*
    Gives the rebels a new Antistasi task of the given type, through Antistasi's own mission request
    (which picks a suitable site, or none, and announces the task). Scheduled environment only.

    Arguments:
    0: Mission type: assassination, conquest, destroy, logistics, supplies, rescue or convoy <STRING>
*/
params ["_missionType"];

if (isNil "A3A_fnc_missionRequest") exitWith { diag_log "[AI Director] offer_mission: Antistasi is not running" };
private _code = createHashMapFromArray [
    ["assassination", "AS"], ["conquest", "CON"], ["destroy", "DES"], ["logistics", "LOG"],
    ["supplies", "SUPP"], ["rescue", "RES"], ["convoy", "CONVOY"]
] getOrDefault [_missionType, ""];
if (_code == "") exitWith { diag_log format ["[AI Director] offer_mission: unknown mission type %1", _missionType] };

diag_log format ["[AI Director] Requesting %1 (%2) mission", _missionType, _code];
// Silent: no "no mission available" chat from Petros; a created task is announced as usual.
private _tasksBefore = +A3A_activeTasks;
[_code, clientOwner, true] call A3A_fnc_missionRequest;
// Antistasi starts the task through its scheduler; give it a moment before reporting failure.
private _deadline = time + 30;
waitUntil { sleep 2; A3A_activeTasks isNotEqualTo _tasksBefore || { time > _deadline } };
if (A3A_activeTasks isEqualTo _tasksBefore) then {
    ["outcome", format ["Your offer_mission (%1): Antistasi found no suitable site; no mission was created", _missionType]]
        call AID_fnc_event;
};
