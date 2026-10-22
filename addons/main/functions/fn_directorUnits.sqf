/*
    Returns how many director-spawned soldiers are alive, and forgets groups that are gone (despawned or
    deleted when empty). Server only.
*/
AID_spawnedGroups = AID_spawnedGroups select { !isNull _x };
private _alive = 0;
{ _alive = _alive + ({ alive _x } count units _x) } forEach AID_spawnedGroups;
_alive
