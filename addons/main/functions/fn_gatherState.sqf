/*
    Returns the game state the director decides on, as a JSON string. Antistasi values are -1 when the
    mission is not Antistasi, so the director also works in a plain editor mission.

    Besides the snapshot, it carries the director's feedback: the events since the last state (see
    AID_fnc_feedback) and its encounters still under way.

    Arguments:
    0: New request from the host, sent once, or "" <STRING>
    1: New story arc request, sent once: ["start", idea] or ["stop", ""], or [] <ARRAY>
    2: Events to report (see AID_fnc_initFeedback) <ARRAY>
    3: From the self-test: the companion always asks Claude <BOOL>
*/
params [["_request", "", [""]], ["_arcRequest", [], [[]]], ["_events", [], [[]]], ["_selfTest", false, [false]]];

private _hq = ["", "Synd_HQ"] select ("Synd_HQ" in allMapMarkers);
private _places = if (isNil "markersX" || { isNil "sidesX" }) then { [] } else { markersX + citiesX - ["Synd_HQ"] };

private _players = (allPlayers - entities "HeadlessClient_F") apply {
    private _player = _x;
    private _info = createHashMapFromArray [
        ["name", name _player],
        ["alive", alive _player],
        ["down", lifeState _player == "INCAPACITATED"],
        ["damage", round (100 * damage _player) / 100],
        ["pos", (getPosATL _player) apply { round _x }],
        ["in_vehicle", !isNull objectParent _player],
        ["vehicle", ["", getText (configOf objectParent _player >> "displayName")] select !isNull objectParent _player],
        ["group_size", { alive _x } count units group _player],
        ["at_hq", _hq != "" && { _player distance2D markerPos _hq < AID_hqRadius }],
        ["nearby_enemies_1km", {
            alive _x && { [side group _player, side group _x] call BIS_fnc_sideIsEnemy }
        } count (_player nearEntities ["CAManBase", 1000])],
        // Friendly soldiers around them (garrisons, recruits, AI squads), so a player in a big fight isn't "alone".
        ["nearby_friendlies_1km", {
            alive _x && { _x != _player } && { side group _x == side group _player }
        } count (_player nearEntities ["CAManBase", 1000])],
        ["squads_commanded", count hcAllGroups _player]
    ];
    if (_hq != "") then { _info set ["distance_to_hq", round (_player distance2D markerPos _hq)] };
    // Where they are in Antistasi's world: the nearest named location and who holds it.
    if (_places isNotEqualTo []) then {
        private _nearest = [_places, _player] call BIS_fnc_nearestPosition;
        _info set ["near", createHashMapFromArray [
            ["place", [_nearest] call AID_fnc_placeName],
            ["held_by", [sidesX getVariable [_nearest, sideUnknown]] call AID_fnc_sideName],
            ["distance", round (_player distance2D markerPos _nearest)]
        ]];
        // Enemy-held locations within 3 km, nearest first: targets for allied_assault.
        private _rebels = missionNamespace getVariable ["teamPlayer", independent];
        private _targets = _places select {
            (sidesX getVariable [_x, sideUnknown]) != _rebels && { markerPos _x distance2D _player < 3000 }
        };
        _targets = [_targets, [_player], { markerPos _x distance2D _input0 }, "ASCEND"] call BIS_fnc_sortBy;
        _info set ["enemy_places", (_targets select [0, 4]) apply {
            createHashMapFromArray [
                ["place", [_x] call AID_fnc_placeName],
                ["kind", [_x] call AID_fnc_placeKind],
                ["held_by", [sidesX getVariable [_x, sideUnknown]] call AID_fnc_sideName],
                ["distance", round (_player distance2D markerPos _x)]
            ]
        }];
    };
    _info
};

// The director's encounters still under way (ended ones are reported as events).
private _encounters = AID_encounters apply {
    private _units = _x get "units";
    private _contact = _x get "contact";
    createHashMapFromArray [
        ["action", _x get "action"], ["side", _x get "side"], ["target", _x get "target"],
        ["minutes_ago", round ((time - (_x get "started")) / 60)],
        ["soldiers", count _units], ["alive", { alive _x } count _units],
        ["contact_after_minutes", [-1, round ((_contact - (_x get "started")) / 60)] select (_contact >= 0)]
    ]
};

// Rebel-held locations (not the HQ), nearest to a player first: targets for counterattack, waved_attack and
// punish_town (towns).
private _rebelPlaces = [];
if (_places isNotEqualTo []) then {
    private _rebelSide = missionNamespace getVariable ["teamPlayer", independent];
    private _positions = _players apply { _x get "pos" };
    _rebelPlaces = (_places select { (sidesX getVariable [_x, sideUnknown]) == _rebelSide }) apply {
        private _marker = _x;
        [selectMin ((_positions apply { round (markerPos _marker distance2D _x) }) + [1e6]), _marker]
    };
    _rebelPlaces sort true;
    _rebelPlaces = (_rebelPlaces select [0, 12]) apply {
        _x params ["_distance", "_marker"];
        createHashMapFromArray [
            ["place", [_marker] call AID_fnc_placeName], ["kind", [_marker] call AID_fnc_placeKind],
            ["nearest_player", _distance]
        ]
    };
};
// The support types each enemy has, by the director's names (see AID_supportTypes).
private _supportTypes = createHashMap;
if (!isNil "A3A_supportTypesOcc") then {
    {
        _x params ["_name", "_types"];
        _supportTypes set [_name, (keys AID_supportTypes) select { (AID_supportTypes get _x) in _types }];
    } forEach [["occupants", A3A_supportTypesOcc], ["invaders", A3A_supportTypesInv]];
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
        ["big_attack_in_progress", missionNamespace getVariable ["bigAttackInProgress", false]],
        // Antistasi's own random events (antistasi_event): one at a time, and one Rivals event at a time.
        ["random_event_running", missionNamespace getVariable ["isEventInProgress", false]],
        ["rivals_active", !isNil "A3A_fnc_singleAttack" && { [] call AID_fnc_rivalsActive }],
        ["rivals_event_running", missionNamespace getVariable ["isRivalEventInProgress", false]],
        ["punishments_allowed", !isNil "A3A_fnc_invaderPunish" && { [] call AID_fnc_punishmentsAllowed }],
        ["support_types", _supportTypes],
        ["rebel_places", _rebelPlaces],
        ["locations_held", call {
            private _held = createHashMap;
            { private _owner = [sidesX getVariable [_x, sideUnknown]] call AID_fnc_sideName; _held set [_owner, (_held getOrDefault [_owner, 0]) + 1] } forEach _places;
            _held
        }]
    ]],
    ["players", _players],
    ["events", _events apply { [round ((_x get "time") / 60), _x get "kind", _x get "text"] }],
    ["encounters", _encounters],
    // How well the rebels are doing: the last 30 minutes.
    ["momentum", call {
        private _sum = createHashMapFromArray [["locations_taken", 0], ["locations_lost", 0], ["enemies_killed", 0], ["rebels_lost", 0]];
        private _keys = createHashMapFromArray [["taken", "locations_taken"], ["lost", "locations_lost"], ["kills", "enemies_killed"], ["losses", "rebels_lost"]];
        { _x params ["", "_kind", "_n"]; private _key = _keys get _kind; _sum set [_key, (_sum get _key) + _n] } forEach AID_momentum;
        _sum
    }],
    ["director", createHashMapFromArray [
        ["units_alive", [] call AID_fnc_directorUnits],
        ["units_max", AID_maxDirectorUnits],
        ["personality", AID_personality],
        ["protect_hq", AID_protectHQ],
        ["cooldowns", AID_cooldowns]
    ]],
    // Standing facts from the host (!director note).
    ["host_notes", AID_notes]
];
if (_selfTest) then { _state set ["self_test", true] };
if (_request != "") then { _state set ["request", _request] };
if (_arcRequest isNotEqualTo []) then {
    _arcRequest params ["_kind", "_idea"];
    _state set ["arc_request", createHashMapFromArray [["text", _idea], ["stop", _kind == "stop"]]];
};
toJSON _state
