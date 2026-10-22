/*
    Whether the named player is within AID_hqRadius of the rebel HQ while the HQ is protected (AID_protectHQ
    "director" or "all"). Outside Antistasi there is no HQ, so never.

    Arguments:
    0: Player name <STRING>

    Returns: <BOOL>
*/
params ["_playerName"];
if (AID_protectHQ == "off" || { !("Synd_HQ" in allMapMarkers) }) exitWith { false };
private _player = allPlayers param [allPlayers findIf { name _x == _playerName }, objNull];
!isNull _player && { _player distance2D markerPos "Synd_HQ" < AID_hqRadius }
