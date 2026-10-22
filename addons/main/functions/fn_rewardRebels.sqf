/*
    Sympathisers donate money and recruits to the rebels, through Antistasi's own resource change (which
    applies its recruit limit). Scheduled environment only.

    Arguments:
    0: Reward size, "small" (300 money, 1 recruit) or "large" (1000 money, 3 recruits) <STRING>
*/
params ["_reward"];

if (isNil "A3A_fnc_resourcesFIA") exitWith { diag_log "[AI Director] reward_rebels: Antistasi is not running" };
([[1, 300], [3, 1000]] select (_reward == "large")) params ["_recruits", "_money"];

[_recruits, _money] call A3A_fnc_resourcesFIA;
[format ["Sympathisers have donated %1 money and %2 recruits to the cause.", _money, _recruits]]
    remoteExec ["systemChat", 0];
diag_log format ["[AI Director] Rewarded rebels: %1 money, %2 recruits", _money, _recruits];
