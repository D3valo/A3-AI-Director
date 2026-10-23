/*
    Whether Antistasi Ultimate's Rivals can have events now: enabled for this campaign, discovered by the rebels,
    not yet defeated, and not in a game mode that leaves them out (the same checks as Antistasi's Rivals event loop).

    Returns: <BOOL>
*/
(missionNamespace getVariable ["areRivalsEnabled", false])
    && { missionNamespace getVariable ["areRivalsDiscovered", false] }
    && { !(missionNamespace getVariable ["areRivalsDefeated", false]) }
    && { (missionNamespace getVariable ["gameMode", 1]) != 3 }
