/*
    Shifts the weather to a preset over 5 minutes. Server only; the weather commands sync to clients.

    Arguments:
    0: Preset: clear, overcast, rain, storm or fog <STRING>
*/
params ["_preset"];

private _weather = createHashMapFromArray [
    // [overcast, rain, fog]
    ["clear", [0.1, 0, 0]],
    ["overcast", [0.7, 0, 0.05]],
    ["rain", [0.85, 0.6, 0.05]],
    ["storm", [1, 1, 0.1]],
    ["fog", [0.5, 0, 0.6]]
] getOrDefault [_preset, []];
if (_weather isEqualTo []) exitWith { diag_log format ["[AI Director] change_weather: unknown preset %1", _preset] };
_weather params ["_overcast", "_rain", "_fog"];

private _seconds = 300;
_seconds setOvercast _overcast;
_seconds setRain _rain;
_seconds setFog _fog;
diag_log format ["[AI Director] Weather changing to %1 over %2 s", _preset, _seconds];
