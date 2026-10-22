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
        [_decision getOrDefault ["target_player", ""], _decision getOrDefault ["strength", "fireteam"]] call AID_fnc_spawnPatrol;
    };
    default {
        diag_log format ["[AI Director] Ignoring unknown action: %1", _decision];
    };
};
