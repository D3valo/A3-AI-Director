/*
    The Antistasi marker of a location by the name the director knows it by (see AID_fnc_placeName), or, with no
    name, the enemy-held location nearest to a position within a radius. Returns "" if there is none.

    Arguments:
    0: Name, or "" for the nearest enemy-held location <STRING>
    1: Position to search from <ARRAY or OBJECT>
    2: Search radius, m <NUMBER> (default 3000)

    Returns: <STRING> marker
*/
params ["_name", "_from", ["_radius", 3000]];
if (isNil "markersX" || { isNil "sidesX" }) exitWith { "" };
private _places = markersX + citiesX - ["Synd_HQ"];
if (_name != "") exitWith {
    _places param [_places findIf { ([_x] call AID_fnc_placeName) == _name }, ""]
};
private _rebels = missionNamespace getVariable ["teamPlayer", independent];
private _enemyHeld = _places select {
    (sidesX getVariable [_x, sideUnknown]) != _rebels && { markerPos _x distance2D _from < _radius }
};
if (_enemyHeld isEqualTo []) exitWith { "" };
[_enemyHeld, _from] call BIS_fnc_nearestPosition
