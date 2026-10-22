/*
    Queues an event for the director's next state (see AID_fnc_initFeedback) and logs it.

    Arguments:
    0: Kind: "kills", "player", "location", "attack", "mission", "outcome" or "proposal" <STRING>
    1: What happened, in plain words <STRING>
*/
params ["_kind", "_text"];
AID_eventSeq = AID_eventSeq + 1;
AID_events pushBack createHashMapFromArray [["id", AID_eventSeq], ["time", round time], ["kind", _kind], ["text", _text]];
if (count AID_events > 50) then { AID_events deleteAt 0 };
diag_log format ["[AI Director] Event (%1): %2", _kind, _text];
