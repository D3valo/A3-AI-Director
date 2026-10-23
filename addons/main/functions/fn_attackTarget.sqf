/*
    The Antistasi marker for an attack on a named location, or an error for the director. Shared by the attack
    actions; the rebel HQ is never a location here (see AID_fnc_attackHQ).

    Arguments:
    0: Location name as the director knows it (see AID_fnc_placeName) <STRING>
    1: Attacking side <SIDE>
    2: "town", or "base" for the kinds Antistasi itself attacks: airbase, military base, outpost, seaport, factory,
       resource <STRING>
    3: Sides the location may be held by <ARRAY>

    Returns: <ARRAY> [marker, ""] or ["", what's wrong]
*/
params ["_place", "_side", "_kind", "_holders"];
private _marker = [_place, [0, 0, 0]] call AID_fnc_findPlace;
if (_marker == "") exitWith { ["", format ["no location called %1", _place]] };
private _placeKind = [_marker] call AID_fnc_placeKind;
private _allowed = [AID_attackableKinds, ["town"]] select (_kind == "town");
if !(_placeKind in _allowed) exitWith {
    ["", format ["%1 is of kind %2; this attack needs one of: %3", _place, _placeKind, _allowed joinString ", "]]
};
private _holder = sidesX getVariable [_marker, sideUnknown];
if (_holder == _side) exitWith { ["", format ["%1 is already held by that side", _place]] };
if !(_holder in _holders) exitWith {
    ["", format ["%1 is held by %2", _place, [_holder] call AID_fnc_sideName]]
};
[_marker, ""]
