/*
    Marks enemy groups within 1.5 km of the named player on every player's map for 5 minutes, as intel
    from a sympathiser. Scheduled environment only.

    Enemies are groups of any side hostile to the player's side, apart from civilians.

    Arguments:
    0: Player name <STRING>
*/
params ["_playerName"];

private _target = allPlayers findIf { name _x == _playerName };
if (_target < 0) exitWith { diag_log format ["[AI Director] reveal_enemies: no player named %1", _playerName] };
_target = allPlayers select _target;
private _playerSide = side group _target;

private _groups = allGroups select {
    private _leader = leader _x;
    alive _leader
    && { side _x != civilian }
    && { [_playerSide, side _x] call BIS_fnc_sideIsEnemy }
    && { _leader distance2D _target < 1500 }
};

private _markers = [];
{
    private _marker = createMarker [format ["AID_intel_%1_%2", diag_tickTime, _forEachIndex], getPosATL leader _x];
    // Local changes first, then one global update that sends the whole marker.
    _marker setMarkerTypeLocal "o_inf";
    _marker setMarkerColorLocal "ColorOPFOR";
    _marker setMarkerText format ["%1 (intel)", count units _x];
    _markers pushBack _marker;
} forEach _groups;
[format ["Intel from a sympathiser: %1 enemy groups marked near %2 for 5 minutes.", count _markers, _playerName]]
    remoteExec ["systemChat", 0];
diag_log format ["[AI Director] Revealed %1 enemy groups near %2", count _markers, _playerName];

sleep 300;
{ deleteMarker _x } forEach _markers;
