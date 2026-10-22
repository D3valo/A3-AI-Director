/*
    The side an encounter fights for, and its Antistasi faction template.

    Side: the decision's choice ("occupants" or "invaders"), else AID_patrolSide if set, else Antistasi's
    Occupants, else east. Faction: the Antistasi template of that side, or nil outside Antistasi (or for a side
    that isn't Occupants or Invaders).

    Arguments:
    0: The decision's enemy: "occupants", "invaders" or "" <STRING> (default "")

    Returns: <ARRAY> [side, faction hashmap or nil]
*/
params [["_enemy", "", [""]]];

private _side = switch (_enemy) do {
    case "occupants": { missionNamespace getVariable ["Occupants", east] };
    case "invaders": { missionNamespace getVariable ["Invaders", east] };
    default { missionNamespace getVariable ["AID_patrolSide", missionNamespace getVariable ["Occupants", east]] };
};
if (isNil "A3A_fnc_spawnGroup" || { !(_side in [missionNamespace getVariable "Occupants", missionNamespace getVariable "Invaders"]) }) exitWith {
    [_side, nil]
};
[_side, [A3A_faction_inv, A3A_faction_occ] select (_side == Occupants)]
