---
-- simple player-based networking system, just a temporary solution to tackle the problem of delay-synced NWVars

-- TODO request from client (SetupMove hook), hook and answer from server
-- TODO remove player from syncedPlayer list if disconnected
-- TODO networking limit of 65535 bits
-- TODO add syncing list, like net.WriteX -> decreasing amount of network message and compress into one. Using ply:PushNetworkingData or smth
--			instead of writing string as index, writing number for list index

local plymeta = FindMetaTable("Player")
if not plymeta then
	Error("FAILED TO FIND PLAYER TABLE")

	return
end

if SERVER then
	util.AddNetworkString("TTT2SyncNetworkingData")
	util.AddNetworkString("TTT2SyncNetworkingNewData")
	util.AddNetworkString("TTT2RequestNetworkingData")
	util.AddNetworkString("TTT2RemovePlayerNetworkingData")
end

--[[
firstFound = {value = 0, type = "number", unsigned = true},
lastFound = {value = 0, type = "number", unsigned = true},
roleFound = {value = false, type = "bool"},
bodyFound = {value = false, type = "bool"},
]]--

-- these tables have on server two included tables:
-- 		T1: key == player connected with the data
-- 		T2: key == player the data is about
-- on clients, there is just one table, because the client just needs to know about his own data storage (T1 key == player the data is about)
local lookupTable = lookupTable or {} -- this should not be accessable externally. A simple key-value transformed and networked syncedDataTable copy with same data references!
local syncedDataTable = syncedDataTable or {} -- iteratable table, e.g. {key = lastFound, value = 0, type = "number", unsigned = true}

local function WriteNetworkingData(data, val)
	if CLIENT or not data then return end

	if data.type == "number" then
		if data.unsigned then
			net.WriteUInt(val, data.bits or 32)
		else
			net.WriteInt(val, data.bits or 32)
		end
	elseif data.type == "bool" then
		net.WriteBool(val)
	elseif data.type == "float" then
		net.WriteFloat(val)
	else
		net.WriteString(val)
	end
end

---
-- Returns whether the player is able to receive networking data
-- @return bool
function plymeta:IsNetworkingSynced()
  	return lookupTable[self] ~= nil
end

---
-- Sets the networking data
-- @warning this does not sync the data like a NWVar!
-- @param string key
-- @param table data
-- @param table ply_or_rf
function plymeta:SetNetworkingRawData(key, data, ply_or_rf)
	if data == nil then return end

	local val = data.value
	local plys = ply_or_rf or player.GetAll()
	local tmp = SERVER and {} or nil
	local ply, oldVal
	local missingValPlys = SERVER and {} or nil
	local plyVals = SERVER and {} or nil

	for i = 1, #plys do
		ply = plys[i]

		local dataTbl = SERVER and lookupTable[self][ply][key] or lookupTable[ply][key]

		oldVal = dataTbl and dataTbl.value or nil

		if oldVal ~= nil then
			val = hook.Run("TTT2UpdatingNetworkingData", self, ply, key, oldVal, val) or val
		else
			val = hook.Run("TTT2InitializeNetworkingData", self, ply, key, val) or val
		end

		if oldVal == val then continue end

		dataTbl.value = val

		if CLIENT then continue end

		plyVals[ply] = val

		if oldVal == nil then
			missingValPlys[#missingValPlys + 1] = ply

			continue
		end

		local index = tostring(val)

		tmp[index] = tmp[index] or {}
		tmp[index][#tmp[index] + 1] = ply
	end

	if CLIENT then return end

	if #missingValPlys > 0 then
		self:InsertNewNetworkingData(key, plyVals, data, missingValPlys, tmp)
	end

	local nwStr = GenerateNetworkingDataString(key)

	for val, plyTbl in pairs(tmp) do
		net.Start(nwStr)
		net.WriteEntity(self)

		WriteNetworkingData(data, val)

		net.Send(plyTbl)
	end
end

function plymeta:SetNetworkingBool(key, val)
	self:SetNetworkingRawData(key, {
		value = val,
		type = "bool",
	})
end

function plymeta:SetNetworkingInt(key, val, bits)
	self:SetNetworkingRawData(key, {
		value = val,
		type = "number",
		bits = bits,
	})
end

function plymeta:SetNetworkingUInt(key, val, bits)
	self:SetNetworkingRawData(key, {
		value = val,
		type = "number",
		unsinged = true,
		bits = bits,
	})
end

function plymeta:SetNetworkingFloat(key, val)
	self:SetNetworkingRawData(key, {
		value = val,
		type = "float",
	})
end

function plymeta:SetNetworkingString(key, val)
	self:SetNetworkingRawData(key, {
		value = val,
		type = "string",
	})
end

---
-- Returns the stored networking key
-- @param string key
-- @return any value
function plymeta:GetNetworkingRawData(target, key)
	if not self:IsNetworkingSynced() or not target:IsNetworkingSynced() then return end

	local data = CLIENT and lookupTable[target][key] or lookupTable[self][target][key]
	if data == nil then return end

	return data.value
end

function plymeta:GetNetworkingBool(target, key)
	return tonumber(self:GetNetworkingRawData(target, key) or 0) == 1
end

function plymeta:GetNetworkingInt(target, key)
	return tonumber(self:GetNetworkingRawData(target, key) or 0)
end

function plymeta:GetNetworkingUInt(target, key)
	return tonumber(self:GetNetworkingRawData(target, key) or 0)
end

function plymeta:GetNetworkingFloat(target, key)
	return tonumber(self:GetNetworkingRawData(target, key) or 0)
end

function plymeta:GetNetworkingString(target, key)
	return tostring(self:GetNetworkingRawData(target, key) or "")
end

local function GenerateNetworkingDataString(key)
	return "TTT2SyncNetworkingData_" .. key
end

if SERVER then
	-- TODO loop through plyVals to send compressed net messages
	function plymeta:InsertNewNetworkingData(key, valTbl, data, ply_or_rf, tmp)
		-- reserving network message for networking data
		local nwStr = GenerateNetworkingDataString(key)

		util.AddNetworkString(nwStr)

		for val, plyTbl in pairs(tmp) do
			-- insert new data in networking storage
			local dataTbl = {}
			dataTbl.key = key
			dataTbl.value = val
			dataTbl.type = data.type
			dataTbl.bits = data.bits
			dataTbl.unsinged = data.unsigned

			local index = #syncedDataTable + 1

			syncedDataTable[index] = dataTbl
			lookupTable[key] = dataTbl

			-- adding networking data to synced table and data with the same message
			net.Start("TTT2SyncNetworkingNewData")
			net.WriteEntity(self)

			net.WriteUInt(index - 1, 16) -- there is no table with index 0 so decreasing it
			net.WriteString(key)
			net.WriteString(data.type)
			net.WriteUInt(data.bits - 1, 5) -- max 32 bits
			net.WriteBool(data.unsinged)

			WriteNetworkingData(self, key) -- TODO

			net.Send(plyTbl) -- TODO just if the plys are in tmp tbl too!
		end
	end

	---
	-- Syncs the networking data of a @{Player} with the current @{Player} COMPLETELY
	function plymeta:SyncNetworkingData(ply)
		if not IsValid(ply) or not ply:IsNetworkingSynced() or lookupTable[self][ply] == nil then return end

		net.Start("TTT2SyncNetworkingData")
		net.WriteEntity(ply)

		for k in pairs(lookupTable[self][ply]) do
			WriteNetworkingData(ply, k)
		end

		net.Send(self)
	end

	local function TTT2RequestNetworkingData(_, requestingPly)
		if not IsValid(requestingPly) then return end

		-- create a new player data storage
		syncedDataTable[requestingPly] = {}
		lookupTable[requestingPly] = {}

		local plys = player.GetAll()
		local dataHolder

		for i = 1, #plys do
			dataHolder = plys[i]

			-- insert requesting player with default data for any player (including requestingPly)
			syncedDataTable[dataHolder][requestingPly] = {}
			lookupTable[dataHolder][requestingPly] = {}
		end

		hook.Run("TTT2SyncNetworkingData", requestingPly)

		requestingPly:SyncNetworkingData()
	end
	net.Receive("TTT2RequestNetworkingData", TTT2RequestNetworkingData)

	-- player disconnecting
	hook.Add("PlayerDisconnected", "TTT2RemovePlayerNetworkingData", function(discPly)
		syncedDataTable[discPly] = nil
		lookupTable[discPly] = nil

		local plys = player.GetAll()

		for i = 1, #plys do
			local dataHolder = plys[i]

			syncedDataTable[dataHolder][discPly] = nil
			lookupTable[dataHolder][discPly] = nil
		end
	end)
else
	-- player requesting data
	hook.Add("SetupMove", "TTT2SetupNetworking", function(ply)
		if ply ~= LocalPlayer() or ply.networkInitialized then return end

		ply.networkInitialized = true

		net.Start("TTT2RequestNetworkingData")
		net.SendToServer()
	end)

	local function ReadNetworkingData(ply, k, data)
		if not lookupTable[ply] then return end

		local data = lookupTable[ply][k]
		if not data then return end

		if data.type == "number" then
			if data.unsigned then
				ply:SetNetworkingUInt(k, net.ReadUInt(data.bits or 32))
			else
				ply:SetNetworkingInt(k, net.ReadInt(data.bits or 32))
			end
		elseif data.type == "bool" then
			ply:SetNetworkingBool(k, net.ReadBool())
		elseif data.type == "float" then
			ply:SetNetworkingFloat(k, net.ReadFloat())
		else
			ply:SetNetworkingString(k, net.ReadString())
		end
	end

	local function TTT2SyncNetworkingNewData()
		local ply = net.ReadEntity()
		if not IsValid(ply) then return end

		local index = net.ReadUInt(16) + 1
		local key = net.ReadString()

		-- insert new data in networking storage
		local dataTbl = {}
		dataTbl.key = key
		dataTbl.type = net.ReadString()
		dataTbl.bits = net.ReadUInt(5) + 1 -- max 32 bits
		dataTbl.unsinged = net.ReadBool()
		dataTbl.value = nil

		syncedDataTable[ply] = syncedDataTable[ply] or {}
		syncedDataTable[ply][index] = dataTbl

		lookupTable[ply] = lookupTable[ply] or {}
		lookupTable[ply][key] = dataTbl

		-- TODO
		WriteNetworkingData(ply, key)

		local function RecFnc()
			local ply = net.ReadEntity()
			if not IsValid(ply) then return end

			-- TODO
			ReadNetworkingData(ply, key)
		end
		net.Receive(nwStr, RecFnc)
	end
	net.Receive("TTT2SyncNetworkingNewData", TTT2SyncNetworkingNewData)

	-- TODO
	local function TTT2SyncNetworkingData()
		local ply = net.ReadEntity()
		if not IsValid(ply) then return end

		for k, v in pairs(lookupTable) do
			ReadNetworkingData(ply, k)
		end
	end
	net.Receive("TTT2SyncNetworkingData", TTT2SyncNetworkingData)
end