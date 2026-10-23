/*
    What kind of Antistasi location a marker is, in plain words: "town", "airbase", "military base", "outpost",
    "seaport", "factory", "resource", "roadblock", or "location" for anything else.

    Arguments:
    0: Antistasi marker <STRING>

    Returns: <STRING>
*/
params ["_marker"];
private _kinds = [
    ["citiesX", "town"], ["airportsX", "airbase"], ["milbases", "military base"], ["outposts", "outpost"],
    ["seaports", "seaport"], ["factories", "factory"], ["resourcesX", "resource"], ["controlsX", "roadblock"]
];
(_kinds param [_kinds findIf { _marker in (missionNamespace getVariable [_x select 0, []]) }, ["", "location"]]) select 1
