/**
 * This is very simple AI that was written while I was ill due to having covid-19.
 * I spent only two partial days working on it, therefore it really is intended to be simple.
 * It will try to spread to all cities with buses alone.
 */
class CoronaAI extends AIController {
    // The town we are working right now
    actualTown = null;
    // Some nasty surprise - you have find cargoId in list, you cannot just use i.e. AICargo.CC_PASSENGERS
    // This stores the CargoId for passengers. More in constructor
    passengerCargoId = -1;
    // The towns we want to go through and "spread" there
    towns = null;
    // Keeping the best engines avialable there
    engines = null;
    // For storing all things we built so we can keep eye on them
    existing = [];

    constructor() {
        // Without this you cannot build road, station or depot
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        this.existing = [];

        // Persist passengers
        local list = AICargoList();
        for (local i = list.Begin(); list.IsEnd() == false; i = list.Next()) {
            if (AICargo.HasCargoClass(i, AICargo.CC_PASSENGERS)) {
                this.passengerCargoId = i;
                break;
            }
        }
    }
    function Start() ;
}

/**
 * Äll the logic starts here
 */
function CoronaAI::Start() {
    AICompany.SetName("CoronaAI")
    AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
    while (true) {
        this.Sleep(10);
        this.FindBestEngine();
        // If we dont have enough money, just dont build any other stations and buses there
        if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) > (AICompany.GetMaxLoanAmount() / 10)) {
            this.SelectTown();
            if (this.actualTown != null) {
                BuildStationsAndBuses();
            }
        }
        this.SellUnprofitables();
        this.HandleOldVehicles();
        this.HandleOldTowns();
        this.DeleteUnusedCrap();
    }
}

/**
 * Find best bus for passengers avialable
 */
function CoronaAI::FindBestEngine() {
    local engines = AIEngineList(AIVehicle.VT_ROAD);
    engines.Valuate(AIEngine.GetCargoType)
    engines.KeepValue(this.passengerCargoId);
    engines.Sort(AIList.SORT_BY_VALUE, false);
    engines.KeepTop(1);
    this.engines = engines;
}

/**
 * Initialize towns or select next town
 */
function CoronaAI::SelectTown() {
    if (this.towns == null) {
        AILog.Info("Generating new towns");
        local towns = AITownList();
        towns.Valuate(AITown.GetPopulation);
        towns.Sort(AIList.SORT_BY_VALUE, false);
        this.towns = towns;
    }

    if (this.towns.Count() == 0) {
        this.actualTown = null;
    } else {
        this.actualTown = this.towns.Begin();
        AILog.Info("Size of towns " + this.towns.Count())
        this.towns.RemoveTop(1);
    }
}

/**
 * Core functionality - This will build the stations and buses
 */
function CoronaAI::BuildStationsAndBuses() {
    AILog.Info("City name " + AITown.GetName(this.actualTown));

    local townCenter = AITown.GetLocation(this.actualTown);
    local list = AITileList();
    // Add 16x16 area around city center
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
    // Find only road tiles
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);
    // Find best places for station (that accepts most humans)
    list.Valuate(AITile.GetCargoAcceptance, this.passengerCargoId, 1, 1, 3);
    list.RemoveBelowValue(10);
    list.Sort(AIList.SORT_BY_VALUE, false);

    // Build first road station
    local firstStation = null;
    local tile = list.Begin();
    while (list.IsEnd() == false && firstStation == null) {
        this.BuildRoadDrivethroughStatoin(tile);
        if (AIRoad.IsRoadStationTile(tile)) {
            firstStation = tile;
        }

        tile = list.Next();
    }

    if (firstStation == null) {
        AILog.Info("First station failed, aborting");
        return;
    }

    // Build second station
    local distanceOfStations = 7;
    local secondStation = null;
    while (distanceOfStations > 2 && secondStation == null) {
        local filteredList = AIList();
        filteredList.AddList(list);
        // Allow only far-enough places to be put into selection
        filteredList.Valuate(AIMap.DistanceManhattan, firstStation);
        filteredList.KeepAboveValue(distanceOfStations);
        // Now we have to sort by amount of cargo we gets again
        filteredList.Valuate(AITile.GetCargoAcceptance, this.passengerCargoId, 1, 1, 3);
        filteredList.RemoveBelowValue(10);
        filteredList.Sort(AIList.SORT_BY_VALUE, false);

        if (filteredList.Count() > 0) {
            local tile = filteredList.Begin();
            while (filteredList.IsEnd() == false && secondStation == null) {
                this.BuildRoadDrivethroughStatoin(tile);
                if (AIRoad.IsRoadStationTile(tile)) {
                    secondStation = tile;
                }

                tile = filteredList.Next();
            }
        }
        if (secondStation == null) {
            distanceOfStations = distanceOfStations - 1;
        }
    }

    if (secondStation == null) {
        AILog.Info("Second station failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        return;
    }

    // Find place to build a depot
    list = AITileList();
    list.AddRectangle(townCenter - AIMap.GetTileIndex(8, 8), townCenter + AIMap.GetTileIndex(8, 8));
    list.Valuate(AIRoad.IsRoadTile);
    list.RemoveValue(0);
    list.Valuate(AITile.GetSlope);
    list.KeepValue(AITile.SLOPE_FLAT);
    list.Valuate(AIMap.DistanceManhattan, AITown.GetLocation(this.actualTown));
    list.Sort(AIList.SORT_BY_VALUE, true);

    // Build a depot
    tile = list.Begin();
    local potentialDepot = null;
    local isConnected = false;
    while (list.IsEnd() == false && isConnected == false) {
        for (local i = 0; i < 4; i++) {
            if (i == 0) {
                potentialDepot = tile + AIMap.GetTileIndex(0, 1);
            }
            if (i == 1) {
                potentialDepot = tile + AIMap.GetTileIndex(1, 0);
            }
            if (i == 2) {
                potentialDepot = tile + AIMap.GetTileIndex(0, -1);
            }
            if (i == 3) {
                potentialDepot = tile + AIMap.GetTileIndex(-1, 0);
            }
            if (AITile.GetSlope(potentialDepot) == AITile.SLOPE_FLAT && AITile.IsBuildable(potentialDepot)) {
                AIRoad.BuildRoadDepot(potentialDepot, tile);
                AIRoad.BuildRoad(potentialDepot, tile);
                AILog.Info("Building Depot at: " + AIMap.GetTileX(potentialDepot) + ":" + AIMap.GetTileY(potentialDepot));
                if (AIRoad.AreRoadTilesConnected(tile, potentialDepot)) {
                    AILog.Info("Its Connected");
                    isConnected = true;
                    break;
                } else {
                    // If we built it but we could not connect it to road
                    AITile.DemolishTile(potentialDepot);
                }
            }
        }
        tile = list.Next();
    }

    if (potentialDepot == null) {
        AILog.Info("Depot failed, aborting");
        AIRoad.RemoveRoadStation(firstStation);
        AIRoad.RemoveRoadStation(secondStation);
        return;
    }


    // Buy our first bus in location
    local bus = AIVehicle.BuildVehicle(potentialDepot, this.engines.Begin());
    AIOrder.AppendOrder(bus, firstStation, AIOrder.OF_NONE);
    AIOrder.AppendOrder(bus, secondStation, AIOrder.OF_NONE);
    AIVehicle.StartStopVehicle(bus);

    // Store information about all the stations, town, etc.
    local obj = {
        bus = bus,
        firstStation = firstStation,
        secondStation = secondStation,
        potentialDepot = potentialDepot,
        lastChange = AIDate.GetCurrentDate(),
        actualTown = this.actualTown,
        exists = true
    };
    this.existing.append(obj);

    AILog.Info("End of building");
}

function CoronaAI::BuildRoadDrivethroughStatoin(tile) {
    AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(0, 1), AIRoad.ROADVEHTYPE_BUS, AIBaseStation.STATION_NEW);
    AIRoad.BuildDriveThroughRoadStation(tile, tile + AIMap.GetTileIndex(1, 0), AIRoad.ROADVEHTYPE_BUS, AIBaseStation.STATION_NEW);
}

/**
 * If vehicle is highly unprofitable - just sell it
 */
function CoronaAI::SellUnprofitables() {
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();
    while (vehicles.IsEnd() == false) {
        if ((AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9) && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AILog.Info("Sending unprofitable vehicle to be sold: " + vehicle)
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        if (AIVehicle.IsStoppedInDepot(vehicle) && (AIVehicle.GetProfitLastYear(vehicle) <= AIVehicle.GetRunningCost(vehicle) * -0.9)) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            AILog.Info("Selling unprofitable vehicle " + vehicle);
            AIVehicle.SellVehicle(vehicle);
        }
        vehicle = vehicles.Next();
    }
}

/**
 * Add buses in old towns where we already have stations - if there is enough passengers
 */
function CoronaAI::HandleOldTowns() {
    foreach (obj in this.existing) {
        // we only add bus once per year to avoid spamming it
        if (obj.lastChange + 30 * 12 < AIDate.GetCurrentDate()) {
            local waitingPassengers1 = AIStation.GetCargoWaiting(AIStation.GetStationID(obj.firstStation), this.passengerCargoId);
            local waitingPassengers2 = AIStation.GetCargoWaiting(AIStation.GetStationID(obj.secondStation), this.passengerCargoId);
            if ((waitingPassengers1 > 200 && waitingPassengers2 > 200) || (waitingPassengers1 + waitingPassengers2 > 600)) {
                local newBus = AIVehicle.BuildVehicle(obj.potentialDepot, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Cloning vehicle in " + AITown.GetName(obj.actualTown) + " as there is " + waitingPassengers1 + ":" + waitingPassengers2 + " passengers");
                    AIOrder.AppendOrder(newBus, obj.firstStation, AIOrder.OF_NONE);
                    AIOrder.AppendOrder(newBus, obj.secondStation, AIOrder.OF_NONE);
                    AIVehicle.StartStopVehicle(newBus);
                    obj.lastChange = AIDate.GetCurrentDate();
                }
            }
        }
    }
}

/**
 * If we find out that there is non-used infrastructure - remove it
 */
function CoronaAI::DeleteUnusedCrap() {
    foreach (obj in this.existing) {
        local stationId = AIStation.GetStationID(obj.firstStation);
        local vehiclesInStation = AIVehicleList_Station(stationId);
        if (obj.exists && (vehiclesInStation.Count() == 0)) {
            AILog.Info("Deleting unused things from " + AITown.GetName(obj.actualTown));
            AIRoad.RemoveRoadStation(obj.firstStation);
            AIRoad.RemoveRoadStation(obj.secondStation);
            AIRoad.RemoveRoadDepot(obj.potentialDepot);
            obj.exists = false;
        }
    }
}

/**
 * Selling vehicles that are too old
 */
function CoronaAI::HandleOldVehicles() {
    local vehicles = AIVehicleList();
    local vehicle = vehicles.Begin();
    while (vehicles.IsEnd() == false) {
        // We keep vehicles up to 7 years more than its their official age
        if (AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7 && AIOrder.IsCurrentOrderPartOfOrderList(vehicle)) {
            AIVehicle.SendVehicleToDepot(vehicle);
        }
        if (AIVehicle.IsStoppedInDepot(vehicle) && AIVehicle.GetAgeLeft(vehicle) <= -30 * 12 * 7) {
            local depotLocation = AIVehicle.GetLocation(vehicle);
            local stationId = AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0));
            local vehiclesInStation = AIVehicleList_Station(stationId);
            // If there is just one vehicle in city, we replace it with new one. Otherwise we just sell it.
            if (vehiclesInStation.Count() == 1) {
                local newBus = AIVehicle.BuildVehicle(depotLocation, this.engines.Begin());
                if (AIVehicle.IsValidVehicle(newBus)) {
                    AILog.Info("Only one vehicle " + vehicle + " in station, replacing");
                    AIOrder.ShareOrders(newBus, vehicle);
                    AIVehicle.StartStopVehicle(newBus);
                    AIVehicle.SellVehicle(vehicle);
                }
            } else {
                AILog.Info("Deleting " + vehicle + " there are " + vehiclesInStation.Count() + " other vehicles");
                AIVehicle.SellVehicle(vehicle);
            }
        }
        vehicle = vehicles.Next();
    }
}
