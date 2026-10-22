/*
    How the director names a side: "rebels", "occupants", "invaders", "civilians", or "" for any other.

    Arguments:
    0: Side <SIDE>

    Returns: <STRING>
*/
params ["_side"];
switch (true) do {
    case (_side == (missionNamespace getVariable ["teamPlayer", independent])): { "rebels" };
    case (_side == (missionNamespace getVariable ["Occupants", west])): { "occupants" };
    case (_side == (missionNamespace getVariable ["Invaders", east])): { "invaders" };
    case (_side == civilian): { "civilians" };
    default { "" };
}
