/*
 * This file is part of pAIper.
 *
 * pAIper is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * pAIper is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with pAIper.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Copyright 2013-2014 Aun Johnsen
 */
import("pathfinder.rail", "RailPathFinder", 1);
import("util.MinchinWeb", "MetaLib", 6);

/*
 * TODO:
 *
 * 1) Make a check that we don't try to re-create the company on load
 */

/*
 * The constructor to build the company
 */
class pAIper extends AIController 
{
	_railtype_pipe = 4; // Railtype for pipelines

	constructor()
	{
		::main_instance <- this;
	}
	
    function Save();
    
	function Start();
}

function pAIper::Save()
{
    local save_data = { };

    return save_data;
}

/*
 * Set the company name
 * @param city = name of city -- Trans-{city} Pipelines
 * Default Trans-OpenTTD Pipelines
 */
function pAIper::SetCompanyName(city = "OpenTTD")
{
	AILog.Info(TimeStamp() + "[Board] Setting Company Name");
	local myname = "Trans-" + city + " Pipelines";
	AICompany.SetName(myname);
	AILog.Info(TimeStamp() + "[Board] " + AICompany.GetPresidentName(AICompany.COMPANY_SELF) + 
		" elected board chairman of " + AICompany.GetName(AICompany.COMPANY_SELF));
}

/*
 * Build company headquarter
 */
function pAIper::BuildHQ(town)
{
	AILog.Info(TimeStamp() + "[Constructrion] Building Company HQ in "+ AITown.GetName(town));
	
	local Walker = MetaLib.SpiralWalker();
	Walker.Start(AITown.GetLocation(town));
	local HQBuilt = false;
	while (HQBuilt == false) {
		HQBuilt = AICompany.BuildCompanyHQ(Walker.Walk());
	}


	if (AICompany.GetLoanAmount() > 0 ) {
		AILog.Info(TimeStamp() + "[Finance] Preparing to repay loan");
		local loan = AICompany.GetLoanAmount();
		local interval = AICompany.GetLoanInterval();
		local bankBalance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
		while (1) {
			loan -= interval;
			AICompany.SetLoanAmount(loan);
			bankBalance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
			if (bankBalance < interval) break;
		}
		if (AICompany.GetLoanAmount() == 0) {
			AILog.Info(TimeStamp() + "[Finance] Loan paid completely");
			return; // Loan paid down
		}
	}
}

/*
 * Return a TimeStamp to be used in AILog
 */
function pAIper::TimeStamp() {
	local now = AIDate.GetCurrentDate();
	local year = AIDate.GetYear(now);
	local month = AIDate.GetMonth(now);
	local day = AIDate.GetDayOfMonth(now);
	local aMonth = "";
	local aDay = "";
	if (month < 10) aMonth = "0";
	if (day < 10) aDay = "0";
	return "[" + year + "-" + aMonth + month + "-" + aDay + day + "] ";
}


function pAIper::Start()
{
	AILog.Info(TimeStamp() + "[Startup] pAIper need PIPE NewGRF to work");
	AILog.Info(TimeStamp() + "[Startup] Starting Script");
	/* Reduce loan to minimum from the start, we don't want too much debt */
	AICompany.SetLoanAmount(AICompany.GetLoanInterval());
	/* Evaluate available rail types */
	local railTypes = AIRailTypeList();
	railTypes.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	local rail = railTypes.Begin();
	local i = 0;
	while (1) {
		i++;
		AILog.Info(TimeStamp() + "[Startup] Railtype #"+i+": " + rail + " = " + AIRail.GetName(rail));
		rail = railTypes.Next();
		if (railTypes.IsEnd()) break;
	}
	/* Evaluate pumpable cargoes */
	local cargoList = AICargoList();
	cargoList.Valuate(function(cargo_id, cargo_class) { 
		if(AICargo.HasCargoClass(cargo_id, cargo_class)) return 1; return 0; },  AICargo.CC_LIQUID);
	cargoList.KeepValue(1);
	
	local cargo = cargoList.Begin();
	while (1) {
		AILog.Info(TimeStamp() + "[Startup] " + AICargo.GetCargoLabel(cargo) + " (" + cargo + 
			") is a liquid cargo.");
		cargo = cargoList.Next();
		if (cargoList.IsEnd()) break;
	}
	/* First pumps available in 1860, we need to wait before start */
	while (AIDate.GetYear(AIDate.GetCurrentDate()) < 1860) {
		this.FinanceDepartment();
		AILog.Info(TimeStamp() + "[Board] Not ready for us yet, take a rest");
		this.Sleep(3000);
	}

	this.FinanceDepartment();
	/* Evaluate available engines (pumps) */
	local engineList = AIEngineList(AIVehicle.VT_RAIL);
	engineList.Valuate(AIEngine.GetRailType);
	engineList.KeepValue(_railtype_pipe);
	local testDistance = 5; // number of tiles to test
	engineList.Valuate(AIEngine.GetMaxSpeed);
	engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	local pump = engineList.Begin();
	local speed = AIEngine.GetMaxSpeed(pump); // ~ km per hour
	local distancePerTile = 664; // ~ km per tile 
	local testDuration = ((testDistance * distancePerTile) / speed) / 24; // number of days in transit
	cargoList.Valuate(AICargo.GetCargoIncome, testDistance, testDuration); 
		// second argument is distance in tiles, third is time in days
	cargoList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	cargo = cargoList.Begin();
//	cargo = 3; // for debugging 3=OIL_, 9=WATR, 18=RUBR
	AILog.Warning(TimeStamp() + "[Traffic] " + AICargo.GetCargoLabel(cargo) + 
		" is the best starting cargo");
	engineList.Valuate(AIEngine.GetCapacity);
	i = 0;
	 pump = engineList.Begin();
	while (1) {
		if (engineList.IsEnd()) break;
		i++;
		AILog.Info(TimeStamp() + "[Startup] Engine #"+i+": " + pump + " = " + AIEngine.GetName(pump) + 
			" (" + AIEngine.GetCapacity(pump) + "k litre) " + AIEngine.GetMaxSpeed(pump) + "km/h");
		pump = engineList.Next();
	}
	/* As we should have at least one pump by now, let us try to find our first monymaking route, 
	 * first let us see if there are subsidies for this cargo */
	local subsidyList = AISubsidyList();
	subsidyList.Valuate(AISubsidy.GetCargoType);
	subsidyList.KeepValue(cargo);
	local source_st = null;
	local dest_st = null;
	local subsidyCount = subsidyList.Count();
	if (subsidyCount > 0) {
		subsidyList.Valuate(function(sub) { if (AISubsidy.IsAwarded(sub)) return 0; return 1; } );
		subsidyList.KeepValue(1);
		subsidyCount = subsidyList.Count();
		if (subsidyCount > 0) {
			/* Build route for a subsidy */
			AILog.Warning(TimeStamp() + "[Board] We can build a subsidy route");
			sub = subsidyList.Begin();
			local source = AISubsidy.GetSourceIndex(sub);
			local dest = AISubsidy.GetDestinationIndex(sub);
			source_st = this.BuildStation(source, cargo);
			dest_st = this.BuildStation(dest, cargo);
			this.BuildRails(source_st, dest_st);
		} else AILog.Error(TimeStamp() + "[Network] All subsidies for " + AICargo.GetCargoLabel(cargo) + 
			" taken!");
	} else {
		AILog.Warning(TimeStamp() + "[Network] No subsidies for " + AICargo.GetCargoLabel(cargo));
		/** We need to search for a good route ourselves */
		local indSList = AIIndustryList();
//		if (AICargo.GetCargoLabel(cargo) == "OIL_") {
			/* Remove Oil Rigs */
			indSList.Valuate(function(idx) { if (AIIndustry.IsBuiltOnWater(idx)) return 1; return 0; } );
			indSList.KeepValue(0);
//		}
		indSList.Valuate(AIIndustry.GetLastMonthTransported, cargo);
		indSList.KeepValue(0);
		indSList.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		indSList.KeepTop(10);
		local startInd = indSList.Begin();
		source_st = null;
		while (!source_st) {
			if (indSList.IsEnd()) break;
			source_st = this.BuildStation(AIIndustry.GetLocation(startInd), cargo);
			startInd = indSList.Next();
		}
		local indDList = ListAcceptingIndustries(AIBaseStation.GetLocation(source_st), cargo, 100);
		indDList.Valuate(AIBase.RandItem);
		indDList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		local endInd = indDList.Begin();
		while (!dest_st) {
			if (indDList.IsEnd()) break;
			dest_st = this.BuildStation(AIIndustry.GetLocation(endInd), cargo);
			endInd = indDList.Next();
		}
		if (source_st == null || dest_st == null) {
			AILog.Warning(TimeStamp() + "[Network] Could not create a startup route, let us wait a" +
				"little and try again");
		} else {
			this.BuildRails(source_st, dest_st);
		}
	}
	/* We should have a route, let us name our company */
	if (AICompany.GetName(AICompany.COMPANY_SELF).find("pAIper") == null) {
		local town = "OpenTTD";
		if (source_st) town = AITile.GetClosestTown(AIStation.GetLocation(source_st));
		this.SetCompanyName(AITown.GetName(town));
	}
	this.BuildHQ(AIStation.GetNearestTown(source_st));

	local sleep = 1000;
	/* From now on we stay in this loop */
	while (1) {
		this.FinanceDepartment();
		this.TrafficDepartment();
		this.NetworkDepartment();
		this.Sleep(sleep);
	}
}

/*
 * BuildStation tries to build the stations, and returns the StationID if successfully built
 * @param near = the node of the industry we want to service
 * @param cargoid = the CargoID we want to transport
 * @return StationID if successful, else NULL
 */
function pAIper::BuildStation(near, cargoid)
{
	AIRail.SetCurrentRailType(_railtype_pipe);
	/* Evaluate tiles nearby to see if a station can be built */
	local ind_idx = AIIndustry.GetIndustryID(near);
	local ind_type = AIIndustry.GetIndustryType(ind_idx);
	local town_id = AITile.GetClosestTown(near);
	local station_name = AITown.GetName(town_id) + " " + AIIndustryType.GetName(ind_type);
	AILog.Info(TimeStamp() + "[Construction] Trying to build "+station_name);
	/* Make a code to evaluate whether tile near accepts or produces cargoid */
	local length = 2; // default value, should not be changed
	local platforms = 2; // default value
//	local direction = AIRail.RAILTRACK_NW_SE; // Default ||
	local direction = AIRail.RAILTRACK_NE_SW; // Default --
	local radius = 4;
	
	this.Budgeting(10000);
	/* Evaluate in what direction we want the tracks of the station */
	local tile_list = AITileList();
	tile_list.AddRectangle(near - AIMap.GetTileIndex(radius, radius), near + 
		AIMap.GetTileIndex(radius, radius));
	
	tile_list.Valuate(AIBase.RandItem); // Avoid building similar layouts all the time
	tile_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	local i = 0;
	local current_tile = tile_list.Begin();
	for (current_tile = tile_list.Begin(); !tile_list.IsEnd(); current_tile = tile_list.Next()) {
		if (!AIMap.IsValidTile(current_tile)) AILog.Error(TimeStamp() + 
			"Error: False current_tile in BuildStation()");
		if (AIRail.BuildRailStation(current_tile, direction, platforms, length, 
			AIStation.STATION_NEW)) break;
	}
	if (!AIRail.IsRailStationTile(current_tile)) return null;
	local station = AIStation.GetStationID(current_tile);
	/* We want to name our stations according to type */
//	this.Sleep(3); // Coffee time
	while(!AIBaseStation.SetName(station, station_name)) {
		i++;
		station_name = AITown.GetName(town_id) + " " + AIIndustryType.GetName(ind_type) + " #"+i;
		
		if (i > 5) break; // If we can't set the station name until now, give up
	}
	AILog.Info(TimeStamp() + "[Construction] " +AIBaseStation.GetName(station) + " successfully built");
	this.FinanceDepartment();
	return station;
}

/*
 * BuildRails runs the pathfinder, and tries to build the pipeline between our points
 */
function pAIper::BuildRails(from, to)
{
	if (from == null || to == null) {
		AILog.Error(TimeStamp() + "[Construction] Trying to build pipe to or from NULL");
		return;
	}
	AIRail.SetCurrentRailType(_railtype_pipe);
	AILog.Info(TimeStamp() + "[Construction] Preparing construction of pipe between " + 
		AIBaseStation.GetName(from)+" and "+AIBaseStation.GetName(to));
	local tile_from = AIStation.GetLocation(from);
	local tile_to = AIStation.GetLocation(to);
	AILog.Info(TimeStamp() + "[Construction] Distance is " + 
		AIMap.DistanceManhattan(tile_from, tile_to) + " tiles manhattan");
	local pathfinder = RailPathFinder();
	
	/* Setting some variables in the pathfinder */
	pathfinder.cost.max_bridge_length = 16;
	pathfinder.cost.max_tunnel_length = 8;
	pathfinder.cost.max_cost = AICompany.GetMaxLoanAmount();
	
	local direction_from = AIRail.GetRailStationDirection(tile_from);
	local direction_to = AIRail.GetRailStationDirection(tile_to);
	/* Find station direction for these */
	local behind_from = tile_from + AIMap.GetTileIndex(-1, 0);
	local behind_to = tile_to + AIMap.GetTileIndex(-1, 0);
	/* Initialize Pathfinder */
	pathfinder.InitializePath([[tile_from, behind_from]], [[behind_to, tile_to]]);
	/* Pathfinding */
	local path = pathfinder.FindPath(-1); // Iterations, -1 = until path found
	
	if (path == null) {
		AILog.Error(TimeStamp() + "[Construction] RailPathFinder returned NULL");
		return;
	}
	
	this.Budgeting( AIMap.DistanceManhattan(tile_from, tile_to) * 100 ); // need to be adjusted
	/* Now that we have money, let us build the route */
	local prev = null;
	local prepprev = null;
	while (path != null) {
		if (prevprev != null) {
			if (AIMap.DistanceManhattan(prev, path.GetTile()) > 1) {
				if (AITunnel.GetOtherTunnelEnd(prev) == path.GetTile()) {
					AITunnel.BuildTunnel(AIVehicle.VT_RAIL, prev);
				} else {
					local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), 
						prev) + 1);
					bridge_list.Valuate(AIBridge.GetMaxSpeed);
					bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
					AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, path.GetTile());
				}
				prevprev = prev;
				prev = path.GetTile();
				path = path.GetParent();
			} else {
				AIRail.BuildRail(prevprev, prev, path.GetTile());
			}
		}
		if (path != null) {
			prevprev = prev;
			prev = path.GetTile();
			path = path.GetParent();
		}
	}
	AILog.Info(TimeStamp() + "[Construction] Completed building");
	this.FinanceDepartment();
}

/*
 * FinanceDepartment takes care of book-keeping, make sure we don't run out of cash, and pay 
 * down on loan as long as we have money
 */
function pAIper::FinanceDepartment()
{
	if (AICompany.GetLoanAmount() > 0 && 
		AICompany.GetLoanInterval() < AICompany.GetBankBalance(AICompany.COMPANY_SELF)) {
			AICompany.SetLoanAmount( AICompany.GetLoanAmount() - AICompany.GetLoanInterval() );
			AILog.Info(TimeStamp() + "[Finance] Paid off a chunk on the loan");
	}
	if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 1) {
		if (AICompany.GetMaxLoanAmount() > AICompany.GetLoanAmount()) {
			AICompany.SetLoanAmount( AICompany.GetLoanAmount() + AICompany.GetLoanInterval() );
			AILog.Info(TimeStamp() + "[Finance] Running low in cash, increasing loan");
		} else {
			AILog.Error(TimeStamp() + "[Finance] We are bankrupt soon if we don't start to make money!");
		}
	}
	AILog.Info(TimeStamp() + "[Finance] Books and Accounts balanced");
}
/*
 * Make sure we have money available for what we plan to do
 */
function pAIper::Budgeting(needed)
{
	AILog.Info(TimeStamp() + "[Board] Finance Department contacted, reserving " + needed + 
		" for purpose");
	local bank = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	local loan = AICompany.GetLoanAmount();
	local maxLoan = AICompany.GetMaxLoanAmount();
	
	if (bank > needed) return; // We have enough money
	local toLoan = needed - bank;
	if ( (toLoan + loan) > maxLoan) { // We can't make it
		AICompany.SetLoanAmount(maxLoan); // but are trying anyway
		AILog.Info(TimeStamp() + "[Planning] Increasing loan to MAX in order to try to achieve our" +
			" goal");
		return;
	}
}
/*
 * The TrafficDepartment takes care of checking if we run at capacity.
 * If we have outdated models, upgrade
 * If we have cargo heaping up, get more pumps
 * If we have excessive waiting, sell
 */
function pAIper::TrafficDepartment()
{
	/* */
	AILog.Info(TimeStamp() + "[Traffic] Analysing network capacity");
}
/*
 * The NetworkDepartment takes care of checking the network, and add new nodes and lines
 */
function pAIper::NetworkDepartment()
{
	/* */
	AILog.Info(TimeStamp() + "[Network] Analysing existing network");
}

/*
 * A simple test that IndustryType accepts CargoID
 */
function pAIper::IndustryTypeAcceptCargo(ind, cargo)
{
	local accept_cargo = AIIndustryType.GetAcceptedCargo(ind);
	local test = null;
	for (test = accept_cargo.Begin(); !accept_cargo.IsEnd(); test = accept_cargo.Next()) {
		if (test == cargo) return true;
	}
	return false;
}

/*
 * Getting a list of IndustryTypes accepting a CargoID
 */
function pAIper::CargoAccepters(cargo)
{
	local type_table = AIIndustryTypeList();
	local return_table = AISignList();
	return_table.Clear();
	local test = null;
	for (test = type_table.Begin(); !type_table.IsEnd(); test = type_table.Next()) {
		if (this.IndustryTypeAcceptCargo(test, cargo)) {
			return_table.AddItem(test, test);
		}
	}
	return return_table;
}

/*
 * Create a list of industries accepting a specific CargoID
 * @param near = a tile to base the test from
 * @param cargo = CargoID to accept
 * @param radius = the accepting radius, default to 512 tiles manhattan
 */
function pAIper::ListAcceptingIndustries(near, cargo, radius = 512)
{
	if (!AIMap.IsValidTile(near)) {
		AILog.Error(TimeStamp()+"Not valid tile in ListAcceptingIndustries: "+near);
		return null;
	}
	if (!AICargo.IsValidCargo(cargo)) {
		AILog.Error(TimeStamp()+"Not valid cargo in ListAcceptingIndustries: "+cargo);
	}
	local table = AISignList();
	table.Clear();
	local accepters = CargoAccepters(cargo);
	accepters.Valuate(function(idx) { return idx; });
	local test = accepters.Begin();
	for (test = accepters.Begin(); !accepters.IsEnd(); test = accepters.Next()) {
		local tmp = AIIndustryList();
		tmp.Valuate(AIIndustry.GetIndustryType);
		tmp.KeepValue(test);
		table.AddList(tmp);
		local addMe = null;
		for (addMe = tmp.Begin(); !tmp.IsEnd(); addMe = tmp.Next()) {
			table.AddItem(addMe, cargo);
		}
	}
	table.Valuate(AIIndustry.GetDistanceManhattanToTile, near);
	table.KeepBelowValue(radius);
		
	return table;
}