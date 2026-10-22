class CfgPatches
{
    class ai_director_main
    {
        name = "AI Director";
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.20;
        requiredAddons[] = {"A3_Functions_F"};
        author = "D3valo";
    };
};

class CfgFunctions
{
    class AID
    {
        class main
        {
            file = "\x\ai_director\addons\main\functions";
            class init { postInit = 1; };
            class loop {};
            class gatherState {};
            class onCallback {};
            class dispatch {};
            class approve {};
            class spawnPatrol {};
            class directorUnits {};
            class selfTest {};
            class callSupport {};
            class offerMission {};
            class launchOffensive {};
            class revealEnemies {};
            class rewardRebels {};
            class changeWeather {};
            class initChat {};
            class chatCommand {};
        };
    };
};
