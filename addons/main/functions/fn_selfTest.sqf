/*
    In-game self-test: checks the extension, the game state, the round trip to the companion and Claude, and
    runs every action against a player, reporting PASS, WARN or FAIL to that player's chat and to the .rpt
    ("[AI Director] TEST ..."). Server only, scheduled. Start it with !director test (or test full), or
    [name player, false] spawn AID_fnc_selfTest from the debug console (server exec).

    The director is paused while it runs. It changes the game like the real actions do: a test patrol (deleted
    at the end), a narration hint, intel markers, overcast weather, and in Antistasi a small donation, a new
    mission and a support call against the player. "full" also launches an Antistasi offensive, which may attack
    the HQ: use it on a throwaway save.

    Arguments:
    0: Name of the player to test against <STRING>
    1: Also test launch_offensive <BOOL>
    2: Machine to send chat replies to (remoteExecutedOwner of the command) <NUMBER>
*/
if (!isServer) exitWith {};
params [["_playerName", "", [""]], ["_full", false, [false]], ["_owner", 2, [0]]];

if (!isNil "AID_testRunning") exitWith {
    ["[Director test] Already running."] remoteExec ["systemChat", _owner];
};
private _target = allPlayers param [allPlayers findIf { name _x == _playerName }, objNull];
if (isNull _target) exitWith {
    [format ["[Director test] No player named %1.", _playerName]] remoteExec ["systemChat", _owner];
};
AID_testRunning = true;
private _wasEnabled = AID_enabled;
AID_enabled = false;
AID_pending = nil;

private _results = [];
private _report = {
    params ["_check", "_ok", "_detail", ["_warnOnly", false]];
    private _status = ["FAIL", "WARN"] select _warnOnly;
    if (_ok) then { _status = "PASS" };
    _results pushBack _status;
    private _line = format ["%1 %2: %3", _status, _check, _detail];
    diag_log format ["[AI Director] TEST %1", _line];
    [format ["[Director test] %1", _line]] remoteExec ["systemChat", _owner];
};
private _waitFor = {
    params ["_condition", "_seconds"];
    private _deadline = diag_tickTime + _seconds;
    waitUntil { sleep 1; call _condition || { diag_tickTime > _deadline } };
    call _condition
};

[format ["[Director test] Testing against %1; the director is paused until the test ends.", _playerName]]
    remoteExec ["systemChat", _owner];

// Records from here on are the test's own; they are removed at the end so the director isn't told about them.
private _eventSeqBefore = AID_eventSeq;
private _encounterSeqBefore = AID_encounterSeq;
// Hostile actions are never aimed at a player at the protected HQ, and the test keeps to that too.
private _hostileOK = !([_playerName] call AID_fnc_atProtectedHQ);
private _skip = {
    [_this, false, "skipped: you are at the protected HQ; move away from it (or !director hq off) to test this", true]
        call _report;
};

// Plumbing
private _version = "ai_director" callExtension ["version", []];
["extension", (_version select 1) == 0, format ["version %1", _version select 0]] call _report;

private _state = fromJSON ([""] call AID_fnc_gatherState);
private _antistasiState = _state getOrDefault ["antistasi", createHashMap];
private _antistasi = !isNil "A3A_fnc_requestSupport" && { (_antistasiState getOrDefault ["war_level", -1]) >= 0 };
["game state", count (_state getOrDefault ["players", []]) > 0, format [
    "%1 players, Antistasi war level %2, money %3, missions %4",
    count (_state getOrDefault ["players", []]), _antistasiState get "war_level",
    _antistasiState get "rebel_money", _antistasiState get "active_missions"
]] call _report;
["Antistasi", _antistasi, ["not detected: Antistasi-only actions are skipped", "detected"] select _antistasi, true]
    call _report;

AID_lastCallback = nil;
"ai_director" callExtension ["send_state", [["", [], [], true] call AID_fnc_gatherState]];
private _replied = [{ !isNil "AID_lastCallback" }, 150] call _waitFor;
if (_replied) then {
    AID_lastCallback params ["", "_function", "_data"];
    private _decision = if (_function == "decision") then { fromJSON _data } else { createHashMap };
    ["companion and Claude", _function == "decision", [
        format ["companion error: %1", _data],
        format ["decided %1: %2", _decision get "action", _decision get "reason"]
    ] select (_function == "decision")] call _report;
} else {
    ["companion and Claude", false, "no reply within 150 s; is the companion running?"] call _report;
};

// Actions
createHashMapFromArray [["action", "narrate"], ["message", "Director self-test: this hint is the narrate action."]]
    call AID_fnc_dispatch;
["narrate", true, "a hint was sent to every player; check it appeared"] call _report;

private _groupsBefore = +AID_spawnedGroups;
if (_hostileOK) then { [_playerName, "fireteam"] call AID_fnc_spawnPatrol };
private _testGroups = AID_spawnedGroups - _groupsBefore;
if (!_hostileOK) then { "spawn_patrol" call _skip } else { if (_testGroups isEqualTo []) then {
    ["spawn_patrol", false, "no patrol spawned; see the .rpt"] call _report;
} else {
    private _group = _testGroups select 0;
    private _leader = leader _group;
    private _expectedSide = missionNamespace getVariable ["AID_patrolSide", missionNamespace getVariable ["Occupants", east]];
    ["spawn_patrol", side _group == _expectedSide && { units _group isNotEqualTo [] }, format [
        "%1 soldiers, side %2 (expected %3), leader %4 (unit type %5), %6 m away",
        count units _group, side _group, _expectedSide, typeOf _leader,
        _leader getVariable ["unitType", "none"], round (_leader distance2D _target)
    ]] call _report;
}; };

private _cap = AID_maxDirectorUnits;
AID_maxDirectorUnits = [] call AID_fnc_directorUnits;
private _countBefore = count AID_spawnedGroups;
[_playerName, "fireteam"] call AID_fnc_spawnPatrol;
["soldier cap", count AID_spawnedGroups == _countBefore, "a patrol over the cap was refused"] call _report;
AID_maxDirectorUnits = _cap;

[_playerName] spawn AID_fnc_revealEnemies;
sleep 3;
private _markers = allMapMarkers select { _x find "AID_intel_" == 0 };
["reveal_enemies", true, format ["%1 enemy groups marked for 5 minutes (0 is right if none are within 1.5 km)",
    count _markers]] call _report;

["overcast"] call AID_fnc_changeWeather;
["change_weather", abs (overcastForecast - 0.7) < 0.05,
    format ["overcast heading for %1 (expected 0.7)", overcastForecast], true] call _report;

if (_antistasi) then {
    private _money = server getVariable ["resourcesFIA", 0];
    ["small"] call AID_fnc_rewardRebels;
    private _gained = (server getVariable ["resourcesFIA", 0]) - _money;
    ["reward_rebels", _gained >= 300, format ["rebel money %1 -> %2", _money, _money + _gained]] call _report;

    private _codes = [["convoy", "CONVOY"], ["logistics", "LOG"], ["destroy", "DES"], ["rescue", "RES"],
        ["supplies", "SUPP"], ["conquest", "CON"], ["assassination", "AS"]];
    private _free = _codes select { !((_x select 1) in A3A_activeTasks) };
    if (_free isEqualTo []) then {
        ["offer_mission", true, "every mission type is already active; nothing to offer", true] call _report;
    } else {
        private _tasksBefore = +A3A_activeTasks;
        [(_free select 0) select 0] call AID_fnc_offerMission;
        private _created = [{ A3A_activeTasks isNotEqualTo _tasksBefore }, 30] call _waitFor;
        ["offer_mission", _created, [
            format ["no %1 task within 30 s (Antistasi may have found no suitable site); see the .rpt", (_free select 0) select 0],
            format ["active missions now %1", A3A_activeTasks]
        ] select _created, true] call _report;
    };

    private _strikesBefore = +(missionNamespace getVariable ["A3A_supportStrikes", []]);
    private _activeBefore = +(missionNamespace getVariable ["A3A_activeSupports", []]);
    if (_hostileOK) then { [_playerName] call AID_fnc_callSupport };
    private _sent = _hostileOK && { [{
        ((missionNamespace getVariable ["A3A_supportStrikes", []]) findIf { !(_x in _strikesBefore) } >= 0)
        || { (missionNamespace getVariable ["A3A_activeSupports", []]) findIf { !(_x in _activeBefore) } >= 0 }
    }, 20] call _waitFor };
    if (!_hostileOK) then { "call_support" call _skip } else { ["call_support", _sent, [
        "Antistasi sent nothing (low defence resources or no safe option); see 'support' lines in the .rpt",
        "Antistasi sent a support; expect a QRF, fire or aircraft"
    ] select _sent, true] call _report; };

    if (_full) then {
        [] call AID_fnc_launchOffensive;
        private _attacking = [{ missionNamespace getVariable ["bigAttackInProgress", false] }, 20] call _waitFor;
        ["launch_offensive", _attacking, [
            "no big attack started (Antistasi may have chosen a convoy, or found no target); see the .rpt",
            "a major Antistasi attack has started"
        ] select _attacking, true] call _report;
    };
};

// Encounters. The soldier cap is lifted meanwhile so earlier director soldiers can't fail the test.
private _encounterGroupsBefore = +AID_spawnedGroups;
private _newGroups = { AID_spawnedGroups select { !(_x in _encounterGroupsBefore) && { !isNull _x } } };
private _inVehicle = { (call _newGroups) findIf { units _x findIf { !isNull objectParent _x } >= 0 } >= 0 };
private _markerExists = { params ["_prefix"]; allMapMarkers findIf { _x find _prefix == 0 } >= 0 };
AID_maxDirectorUnits = 1e6;

AID_lastInformant = objNull;
[_playerName, "Director self-test: I am the informant. Walk up to me."] spawn AID_fnc_informant;
private _walking = [{ !isNull AID_lastInformant }, 10] call _waitFor;
["informant", _walking, ["no informant appeared; see the .rpt",
    format ["a civilian is walking to you from %1 m; reach them for a hint and intel markers",
        round (AID_lastInformant distance2D _target)]] select _walking] call _report;

if (_antistasi && { !_hostileOK }) then {
    { _x call _skip } forEach ["vehicle_patrol", "roadblock", "sniper_team", "heli_recon", "enemy_vip"];
    [_playerName] spawn AID_fnc_supplyDrop;
    private _dropping = [{ ["AID_drop_"] call _markerExists }, 15] call _waitFor;
    ["supply_drop", _dropping, "a crate is parachuting in nearby, marked on the map"] call _report;
};
if (_antistasi && { _hostileOK }) then {
    [_playerName] call AID_fnc_vehiclePatrol;
    ["vehicle_patrol", call _inVehicle, "an armed vehicle with a fireteam (see the .rpt for type and distance)"]
        call _report;

    private _before = count (call _newGroups);
    [_playerName] call AID_fnc_roadblock;
    ["roadblock", count (call _newGroups) > _before,
        "a vehicle and a fireteam on a road ahead of you (a WARN-worthy miss if you are far from roads)", true]
        call _report;

    _before = count (call _newGroups);
    [_playerName] call AID_fnc_sniperTeam;
    ["sniper_team", count (call _newGroups) > _before, "a sniper and spotter on high ground"] call _report;

    [_playerName] spawn AID_fnc_heliRecon;
    private _flying = [{ (call _newGroups) findIf { (vehicle leader _x) isKindOf "Air" } >= 0 }, 15] call _waitFor;
    ["heli_recon", _flying, ["no helicopter (does the faction have light or transport helicopters?)",
        "a helicopter is inbound; it circles you for two minutes without firing"] select _flying, true] call _report;

    [_playerName] spawn AID_fnc_supplyDrop;
    private _dropping = [{ ["AID_drop_"] call _markerExists }, 15] call _waitFor;
    ["supply_drop", _dropping, "a crate is parachuting in nearby, marked on the map"] call _report;

    [_playerName] spawn AID_fnc_enemyVip;
    private _vip = [{ ["AID_vip_"] call _markerExists }, 30] call _waitFor;
    ["enemy_vip", _vip, "an officer and escort are marked on the map"] call _report;

    _before = count (call _newGroups);
    [_playerName] call AID_fnc_armorAssault;
    ["armor_assault", count (call _newGroups) > _before,
        "armour with infantry on a road 1.2-2 km out (a WARN if the faction has no armour or there is no road)", true]
        call _report;

    _before = count (call _newGroups);
    [_playerName] spawn AID_fnc_airAttack;
    private _inbound = [{ count (call _newGroups) > _before }, 15] call _waitFor;
    ["air_attack", _inbound, ["no attack helicopter (does the faction have one?)", "an attack helicopter is inbound"]
        select _inbound, true] call _report;
};
AID_maxDirectorUnits = _cap;

// Friendly forces and aggression. Rebel soldiers spawned here are removed at the end.
private _rebelUnitsBefore = allUnits select { side group _x == teamPlayer };
private _newRebels = { (allUnits select { side group _x == teamPlayer && { !isPlayer _x } }) - _rebelUnitsBefore };
if (_antistasi) then {
    [_playerName, "fireteam"] call AID_fnc_sendReinforcements;
    ["send_reinforcements", (call _newRebels) isNotEqualTo [], format ["%1 rebel soldiers are joining you", count (call _newRebels)]]
        call _report;

    private _place = ["", _target] call AID_fnc_findPlace;
    if (_place == "") then {
        ["allied_assault", true, "no enemy-held location within 3 km to assault", true] call _report;
    } else {
        private _countBefore = count (call _newRebels);
        [_playerName, "fireteam", ""] call AID_fnc_alliedAssault;
        ["allied_assault", count (call _newRebels) > _countBefore,
            format ["a rebel fireteam is attacking %1", [_place] call AID_fnc_placeName]] call _report;
    };

    ["occupants", 1, 1] call AID_fnc_changeAggression;
    ["change_aggression", true, "the occupiers' aggression was nudged by 1 for 1 minute (see the .rpt)"] call _report;
};

// Clean up the test soldiers and their vehicles; everything else (informant, crate, markers) stays as the real
// actions would leave it. The director forgets the test's encounters and outcomes first: they weren't its doing.
AID_encounters = AID_encounters select { (_x get "id") <= _encounterSeqBefore };
AID_events = AID_events select { (_x get "id") <= _eventSeqBefore || { (_x get "kind") != "outcome" } };
{
    private _group = _x;
    { deleteVehicle objectParent _x; deleteVehicle _x } forEach units _group;
    deleteGroup _group;
} forEach (_testGroups + call _newGroups);
{ deleteVehicle _x } forEach (call _newRebels);

AID_enabled = _wasEnabled;
AID_testRunning = nil;
private _summary = format ["Done: %1 passed, %2 warnings, %3 failed. Director %4.",
    { _x == "PASS" } count _results, { _x == "WARN" } count _results, { _x == "FAIL" } count _results,
    ["off", "on again"] select AID_enabled];
diag_log format ["[AI Director] TEST %1", _summary];
[format ["[Director test] %1", _summary]] remoteExec ["systemChat", _owner];
