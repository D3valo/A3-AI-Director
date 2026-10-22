/*
    Runs a decision. Only the actions listed here can ever run, whatever the companion sends.
*/
private _decision = _this;
switch (_decision getOrDefault ["action", "wait"]) do {
    case "narrate": {
        private _message = _decision getOrDefault ["message", ""];
        if (_message isEqualType "" && {_message != ""}) then {
            [_message select [0, 200]] remoteExec ["hint", 0];
        };
    };
    case "spawn_patrol": {
        // Spawned: this runs from the ExtensionCallback handler or the debug console, which can't sleep.
        [_decision getOrDefault ["target_player", ""], _decision getOrDefault ["strength", "fireteam"]] spawn AID_fnc_spawnPatrol;
    };
    default {
        diag_log format ["[AI Director] Ignoring unknown action: %1", _decision];
    };
};
