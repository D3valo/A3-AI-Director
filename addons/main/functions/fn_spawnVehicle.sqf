/*
    Spawns a crewed enemy vehicle from the faction template the way Antistasi does: crew from
    A3A_fnc_createVehicleCrew, units and vehicle initialised for the attack pool, and the vehicle's resource cost
    plus 10 per crewman charged to the side's attack resources. Antistasi only.

    Arguments:
    0: Side <SIDE>
    1: Faction <HASHMAP>
    2: Template keys to try in order, e.g. ["vehiclesLightArmed", "vehiclesLightUnarmed"] <ARRAY>
    3: Position ATL <ARRAY>
    4: Direction <NUMBER>
    5: Special placement: "NONE" on the ground, "FLY" in the air <STRING> (default "NONE")

    Returns: <ARRAY> [vehicle, crew group], or [] if the template has none of these vehicles
*/
params ["_side", "_faction", "_keys", "_pos", "_dir", ["_special", "NONE"]];

private _key = _keys param [_keys findIf { (_faction getOrDefault [_x, []]) isNotEqualTo [] }, ""];
if (_key == "") exitWith {
    diag_log format ["[AI Director] The faction has no %1", _keys joinString " or "];
    []
};
private _type = selectRandom (_faction get _key);
private _vehicle = createVehicle [_type, _pos, [], 0, _special];
_vehicle setDir _dir;
private _crew = [_side, _vehicle] call A3A_fnc_createVehicleCrew;
{ [_x, "", false, "attack"] call A3A_fnc_NATOinit } forEach units _crew;
[_vehicle, _side, "attack"] call A3A_fnc_AIVEHinit;
private _cost = (A3A_vehicleResourceCosts getOrDefault [_type, 0]) + 10 * count units _crew;
[-_cost, _side, "attack"] call A3A_fnc_addEnemyResources;
AID_spawnedGroups pushBack _crew;
[_vehicle, _crew]
