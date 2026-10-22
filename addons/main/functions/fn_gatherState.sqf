/*
    Returns the game state the director decides on, as a JSON string. Antistasi values are -1 when the
    mission is not Antistasi, so the director also works in a plain editor mission.

    Arguments:
    0: New request from the host, sent once, or "" <STRING>
*/
params [["_request", "", [""]]];

private _players = (allPlayers - entities "HeadlessClient_F") apply {
    private _player = _x;
    createHashMapFromArray [
        ["name", name _player],
        ["alive", alive _player],
        ["damage", round (100 * damage _player) / 100],
        ["pos", (getPosATL _player) apply { round _x }],
        ["in_vehicle", !isNull objectParent _player],
        ["group_size", { alive _x } count units group _player],
        ["at_hq", "Synd_HQ" in allMapMarkers && { _player distance2D markerPos "Synd_HQ" < AID_hqRadius }],
        ["nearby_enemies_1km", {
            alive _x && { [side group _player, side group _x] call BIS_fnc_sideIsEnemy }
        } count (_player nearEntities ["CAManBase", 1000])]
    ]
};

// Antistasi keeps the rebels' money and recruits on its "server" object.
private _rebels = missionNamespace getVariable ["server", objNull];

private _state = createHashMapFromArray [
    ["time", round time],
    ["daytime", round (10 * dayTime) / 10],
    ["world", worldName],
    ["weather", createHashMapFromArray [["overcast", round (100 * overcast) / 100], ["rain", round (100 * rain) / 100], ["fog", round (100 * fog) / 100]]],
    ["antistasi", createHashMapFromArray [
        ["war_level", missionNamespace getVariable ["tierWar", -1]],
        ["aggression_occupants", missionNamespace getVariable ["aggressionOccupants", -1]],
        ["aggression_invaders", missionNamespace getVariable ["aggressionInvaders", -1]],
        // What the occupiers can spend on supports (call_support) and on attacks and patrols.
        ["occupants_defence_resources", round (missionNamespace getVariable ["A3A_resourcesDefenceOcc", -1])],
        ["occupants_attack_resources", round (missionNamespace getVariable ["A3A_resourcesAttackOcc", -1])],
        // The invaders: a second enemy, at war with the occupiers too, usually active later in the war.
        ["invaders_defence_resources", round (missionNamespace getVariable ["A3A_resourcesDefenceInv", -1])],
        ["invaders_attack_resources", round (missionNamespace getVariable ["A3A_resourcesAttackInv", -1])],
        ["occupants_defeated", missionNamespace getVariable ["areOccupantsDefeated", false]],
        ["invaders_defeated", missionNamespace getVariable ["areInvadersDefeated", false]],
        ["rebel_money", _rebels getVariable ["resourcesFIA", -1]],
        ["rebel_recruits", _rebels getVariable ["hr", -1]],
        // Antistasi task codes: AS, CON, DES, LOG, SUPP, RES, CONVOY, ...
        ["active_missions", missionNamespace getVariable ["A3A_activeTasks", []]],
        ["big_attack_in_progress", missionNamespace getVariable ["bigAttackInProgress", false]]
    ]],
    ["players", _players],
    ["director", createHashMapFromArray [
        ["units_alive", [] call AID_fnc_directorUnits],
        ["units_max", AID_maxDirectorUnits],
        ["personality", AID_personality],
        ["protect_hq", AID_protectHQ]
    ]]
];
if (_request != "") then { _state set ["request", _request] };
toJSON _state
