/*
    Whether Antistasi would punish towns now: punishments enabled in the campaign's parameters and the war level
    at least the one they start at (as in A3A_fnc_chooseAttack), with the invaders not defeated.

    Returns: <BOOL>
*/
(missionNamespace getVariable ["enablePunishments", 0]) isEqualTo 1
    && { (missionNamespace getVariable ["tierWar", 0]) >= (missionNamespace getVariable ["A3U_setting_tierWarPunishments", 1e9]) }
    && { !(missionNamespace getVariable ["areInvadersDefeated", false]) }
