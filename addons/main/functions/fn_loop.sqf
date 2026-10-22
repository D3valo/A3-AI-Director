/*
    Sends the game state to the companion every AID_interval seconds while the director is enabled and
    players are connected, and straight away when the host sets AID_request or AID_arcRequest. The decision arrives later
    through the ExtensionCallback handler.
*/
private _next = time + AID_interval;
while { true } do {
    waitUntil { sleep 1; time >= _next || { AID_request != "" } || { AID_arcRequest isNotEqualTo [] } };
    if (AID_enabled && {allPlayers isNotEqualTo []}) then {
        private _request = AID_request;
        private _arcRequest = AID_arcRequest;
        [] call AID_fnc_feedback;
        private _events = +AID_events;
        private _style = AID_personality;
        private _result = "ai_director" callExtension ["send_state", [[_request, _arcRequest, _events] call AID_fnc_gatherState]];
        _result params ["_status", "_code"];
        if (_code != 0) then {
            diag_log format ["[AI Director] send_state failed: %1", _result];
            _next = time + AID_interval;
        };
        if (_status == "sent") then {
            // The companion keeps the request until a decision carries it out.
            if (AID_request isEqualTo _request) then { AID_request = "" };
            if (AID_arcRequest isEqualTo _arcRequest) then { AID_arcRequest = [] };
            // Sent: drop the events it carried; any queued since stay for the next state.
            if (_events isNotEqualTo []) then {
                private _sentUpTo = (_events select -1) get "id";
                AID_events = AID_events select { (_x get "id") > _sentUpTo };
            };
            AID_sentStyle = _style;  // the style this state asked for; see AID_fnc_onCallback
            _next = time + AID_interval;
        };
        // "busy": the previous state is still with the companion, so try again in a second.
    } else {
        _next = time + AID_interval;
    };
};
