/*
    Sends the game state to the companion every AID_interval seconds while the director is enabled and
    players are connected, and straight away when the host sets AID_request. The decision arrives later
    through the ExtensionCallback handler.
*/
private _next = time + AID_interval;
while { true } do {
    waitUntil { sleep 1; time >= _next || {AID_request != ""} };
    if (AID_enabled && {allPlayers isNotEqualTo []}) then {
        private _request = AID_request;
        private _result = "ai_director" callExtension ["send_state", [[_request] call AID_fnc_gatherState]];
        _result params ["_status", "_code"];
        if (_code != 0) then {
            diag_log format ["[AI Director] send_state failed: %1", _result];
            _next = time + AID_interval;
        };
        if (_status == "sent") then {
            // The companion keeps the request until a decision carries it out.
            if (AID_request isEqualTo _request) then { AID_request = "" };
            _next = time + AID_interval;
        };
        // "busy": the previous state is still with the companion, so try again in a second.
    } else {
        _next = time + AID_interval;
    };
};
