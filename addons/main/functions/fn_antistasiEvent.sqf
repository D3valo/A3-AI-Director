/*
    Starts one of Antistasi Ultimate's own random events, the ones its event loops roll by themselves. Each
    picks a random rebel player and checks its own conditions (a frontline, a town, an outpost nearby); if they
    aren't met it ends quietly or Antistasi rolls a different event instead. Antistasi only; scheduled.

    Antistasi runs one random event at a time (isEventInProgress) and one Rivals event at a time
    (isRivalEventInProgress); the director keeps to the same rule. The two Rivals skirmishes clear
    isEventInProgress when they end, not the Rivals flag, so they count as random events.

    Arguments:
    0: Event, as the director names it (see AID_antistasiEvents) <STRING>
*/
params ["_event"];

// The director's name -> [function, flag it runs under]
private _info = AID_antistasiEvents getOrDefault [_event, []];
if (_info isEqualTo []) exitWith { diag_log format ["[AI Director] antistasi_event: unknown event %1", _event] };
_info params ["_function", "_flag"];
if (isNil _function) exitWith { diag_log format ["[AI Director] antistasi_event: %1 is not defined", _function] };
if (missionNamespace getVariable [_flag, false]) exitWith {
    ["outcome", format ["Your antistasi_event %1: not started, another Antistasi event is still running", _event]]
        call AID_fnc_event;
};
if (_flag == "isRivalEventInProgress" && { !([] call AID_fnc_rivalsActive) }) exitWith {
    ["outcome", format ["Your antistasi_event %1: not started, the Rivals are not active", _event]] call AID_fnc_event;
};

diag_log format ["[AI Director] Starting Antistasi event %1 (%2)", _event, _function];
missionNamespace setVariable [_flag, true];
[[], _function] call A3A_fnc_scheduler;
["outcome", format ["Your antistasi_event %1: started. Antistasi places it near a random rebel player, and may end it or roll a different event if it doesn't fit there", _event]] call AID_fnc_event;
