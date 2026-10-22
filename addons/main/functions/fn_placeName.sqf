/*
    A location's name for the director: Antistasi's own (A3A_fnc_localizar), made unique where Antistasi gives
    several markers the same name (several roadblocks near one town, for example) by adding the map grid.
    Cached for the session.

    Arguments:
    0: Antistasi marker <STRING>

    Returns: <STRING>
*/
params ["_marker"];
if (isNil "AID_placeNames") then {
    AID_placeNames = createHashMap;
    private _byName = createHashMap;
    {
        private _name = [_x] call A3A_fnc_localizar;
        _byName set [_name, (_byName getOrDefault [_name, []]) + [_x]];
    } forEach (markersX + citiesX);
    {
        private _markers = _y;
        private _name = _x;
        {
            AID_placeNames set [_x, [_name, format ["%1 (grid %2)", _name, mapGridPosition markerPos _x]] select (count _markers > 1)];
        } forEach _markers;
    } forEach _byName;
};
AID_placeNames getOrDefault [_marker, _marker]
