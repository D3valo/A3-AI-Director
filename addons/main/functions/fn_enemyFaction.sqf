/*
    The side the director's encounters fight for, and its Antistasi faction template.

    Side: AID_patrolSide if set, otherwise Antistasi's Occupants, otherwise east. Faction: the Antistasi template
    of that side, or nil outside Antistasi (or for a side that isn't Occupants or Invaders).

    Returns: <ARRAY> [side, faction hashmap or nil]
*/
private _side = missionNamespace getVariable ["AID_patrolSide", missionNamespace getVariable ["Occupants", east]];
if (isNil "A3A_fnc_spawnGroup" || { !(_side in [missionNamespace getVariable "Occupants", missionNamespace getVariable "Invaders"]) }) exitWith {
    [_side, nil]
};
[_side, [A3A_faction_inv, A3A_faction_occ] select (_side == Occupants)]
