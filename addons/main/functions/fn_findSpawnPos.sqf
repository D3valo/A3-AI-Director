/*
    Finds a position for an encounter: a random point at a distance band from the target, optionally on a road
    and within a bearing, not in water, and (by default) out of sight of every player. Returns [] if none of
    40 tries fits.

    Arguments:
    0: Target <OBJECT>
    1: Minimum distance, m <NUMBER>
    2: Maximum distance, m <NUMBER>
    3: On a road <BOOL> (default false)
    4: Hidden from every player <BOOL> (default true)
    5: Bearing from the target, degrees, or -1 for any <NUMBER> (default -1)
    6: Allowed spread either side of the bearing, degrees <NUMBER> (default 45)

    Returns: <ARRAY> position ATL, or []
*/
params ["_target", "_min", "_max", ["_onRoad", false], ["_hidden", true], ["_bearing", -1], ["_spread", 45]];

private _hiddenFromPlayers = {
    params ["_pos"];
    private _eye = (AGLToASL _pos) vectorAdd [0, 0, 1.7];
    allPlayers findIf {
        _x distance2D _pos < 1500 && { ([objNull, "VIEW"] checkVisibility [eyePos _x, _eye]) > 0.1 }
    } < 0
};

private _found = [];
for "_i" from 1 to 40 do {
    private _dir = [random 360, _bearing - _spread + random (2 * _spread)] select (_bearing >= 0);
    private _candidate = _target getPos [_min + random (_max - _min), _dir];
    if (_onRoad) then {
        private _roads = _candidate nearRoads 200;
        _candidate = if (_roads isEqualTo []) then { [] } else { getPosATL (selectRandom _roads) };
    };
    if (_candidate isNotEqualTo []
        && { !surfaceIsWater _candidate }
        && { _candidate distance2D _target >= _min * 0.8 }
        && { !_hidden || { [_candidate] call _hiddenFromPlayers } }
    ) exitWith { _found = _candidate };
};
_found
