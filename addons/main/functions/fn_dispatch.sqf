/*
    Runs a decision. Only the actions listed here can ever run, whatever the companion sends.
    Actions are spawned: this runs from the ExtensionCallback handler or the debug console, which can't
    sleep, and Antistasi's functions do.
*/
private _decision = _this;
private _target = _decision getOrDefault ["target_player", ""];
switch (_decision getOrDefault ["action", "wait"]) do {
    case "narrate": {
        private _message = _decision getOrDefault ["message", ""];
        if (_message isEqualType "" && {_message != ""}) then {
            [_message select [0, 200]] remoteExec ["hint", 0];
        };
    };
    case "spawn_patrol": { [_target, _decision getOrDefault ["strength", "fireteam"]] spawn AID_fnc_spawnPatrol };
    case "call_support": { [_target] spawn AID_fnc_callSupport };
    case "offer_mission": { [_decision getOrDefault ["mission_type", ""]] spawn AID_fnc_offerMission };
    case "launch_offensive": { [] spawn AID_fnc_launchOffensive };
    case "reveal_enemies": { [_target] spawn AID_fnc_revealEnemies };
    case "reward_rebels": { [_decision getOrDefault ["reward", "small"]] spawn AID_fnc_rewardRebels };
    case "change_weather": { [_decision getOrDefault ["weather", ""]] call AID_fnc_changeWeather };
    case "vehicle_patrol": { [_target] spawn AID_fnc_vehiclePatrol };
    case "roadblock": { [_target] spawn AID_fnc_roadblock };
    case "heli_recon": { [_target] spawn AID_fnc_heliRecon };
    case "sniper_team": { [_target] spawn AID_fnc_sniperTeam };
    case "informant": {
        // Optional: JSON null may come through as nil or as a non-string.
        private _line = _decision getOrDefault ["message", ""];
        if (isNil "_line" || { !(_line isEqualType "") }) then { _line = "" };
        [_target, _line select [0, 200]] spawn AID_fnc_informant;
    };
    case "supply_drop": { [_target] spawn AID_fnc_supplyDrop };
    case "enemy_vip": { [_target] spawn AID_fnc_enemyVip };
    default {
        diag_log format ["[AI Director] Ignoring unknown action: %1", _decision];
    };
};
