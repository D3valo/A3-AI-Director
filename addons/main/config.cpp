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
            class vehiclePatrol {};
            class roadblock {};
            class heliRecon {};
            class sniperTeam {};
            class informant {};
            class supplyDrop {};
            class enemyVip {};
            class findPlayer {};
            class findSpawnPos {};
            class enemyFaction {};
            class capAllows {};
            class spawnVehicle {};
            class spawnInfantry {};
            class atProtectedHQ {};
            class protectHQ {};
            class initFeedback {};
            class feedback {};
            class event {};
            class trackEncounter {};
            class sideName {};
            class placeName {};
            class findPlace {};
            class spawnRebels {};
            class sendReinforcements {};
            class alliedAssault {};
            class changeAggression {};
            class armorAssault {};
            class airAttack {};
            class initChat {};
            class chatCommand {};
        };
    };
};
