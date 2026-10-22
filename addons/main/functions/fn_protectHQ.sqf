/*
    With AID_protectHQ "all", keeps Antistasi's own attacks off the rebel HQ: Antistasi only targets the HQ once a
    side's HQ knowledge reaches 1, so this holds both sides' knowledge just below that, checking every second.
    Relax the setting and the knowledge grows again with the enemy's next sightings, and HQ attacks can return.
    Server only; spawned once by AID_fnc_init.
*/
while { true } do {
    if (AID_protectHQ == "all") then {
        {
            if ((missionNamespace getVariable [_x, 0]) >= 1) then {
                missionNamespace setVariable [_x, 0.99];
                diag_log format ["[AI Director] Protected HQ: held %1 below the attack threshold", _x];
            };
        } forEach ["A3A_curHQInfoOcc", "A3A_curHQInfoInv"];
    };
    sleep 1;
};
