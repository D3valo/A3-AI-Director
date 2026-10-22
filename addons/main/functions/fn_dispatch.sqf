/*
    Runs a decision. Only the actions listed here can ever run, whatever the companion sends.
    Actions are spawned: this runs from the ExtensionCallback handler or the debug console, which can't
    sleep, and Antistasi's functions do.

    With AID_protectHQ "director" or "all", actions that bring enemies to a player don't run while that player is
    within AID_hqRadius of the rebel HQ, and offensives never pick the HQ (see AID_fnc_launchOffensive).
*/
private _decision = _this;
private _optional = {
    // Fields an action doesn't use arrive as JSON null, which may come through as nil or a non-string.
    params ["_key"];
    private _value = _decision getOrDefault [_key, ""];
    if (isNil "_value" || { !(_value isEqualType "") }) then { "" } else { _value }
};
private _action = _decision getOrDefault ["action", "wait"];
private _target = "target_player" call _optional;
private _enemy = "enemy" call _optional;

private _hostile = ["spawn_patrol", "call_support", "vehicle_patrol", "roadblock", "heli_recon", "sniper_team", "enemy_vip"];
if (_action in _hostile && { [_target] call AID_fnc_atProtectedHQ }) exitWith {
    diag_log format ["[AI Director] %1 not run: %2 is at the protected HQ", _action, _target];
};

switch (_action) do {
    case "narrate": {
        private _message = "message" call _optional;
        if (_message != "") then { [_message select [0, 200]] remoteExec ["hint", 0] };
    };
    case "spawn_patrol": { [_target, "strength" call _optional, _enemy] spawn AID_fnc_spawnPatrol };
    case "call_support": { [_target, _enemy] spawn AID_fnc_callSupport };
    case "offer_mission": { ["mission_type" call _optional] spawn AID_fnc_offerMission };
    case "launch_offensive": { [_enemy] spawn AID_fnc_launchOffensive };
    case "reveal_enemies": { [_target] spawn AID_fnc_revealEnemies };
    case "reward_rebels": { ["reward" call _optional] spawn AID_fnc_rewardRebels };
    case "change_weather": { ["weather" call _optional] call AID_fnc_changeWeather };
    case "vehicle_patrol": { [_target, _enemy] spawn AID_fnc_vehiclePatrol };
    case "roadblock": { [_target, _enemy] spawn AID_fnc_roadblock };
    case "heli_recon": { [_target, _enemy] spawn AID_fnc_heliRecon };
    case "sniper_team": { [_target, _enemy] spawn AID_fnc_sniperTeam };
    case "informant": { [_target, ("message" call _optional) select [0, 200]] spawn AID_fnc_informant };
    case "supply_drop": { [_target, _enemy] spawn AID_fnc_supplyDrop };
    case "enemy_vip": { [_target, _enemy] spawn AID_fnc_enemyVip };
    default {
        diag_log format ["[AI Director] Ignoring unknown action: %1", _decision];
    };
};
