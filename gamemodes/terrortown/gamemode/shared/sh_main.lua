---
-- This file contains all shared gamemode hooks needed when the gamemode initializes

local IsValid = IsValid
local hook = hook
local team = team

---
-- Initializes TTT2
-- @hook
-- @register
-- @realm shared
function GM:TTT2Initialize()
	-- load all roles
	roles.OnLoaded()

	hook.Run("TTT2RolesLoaded")
	hook.Run("TTT2BaseRoleInit")

	-- load all HUDs
	huds.OnLoaded()

	-- load all HUD elements
	hudelements.OnLoaded()

	DefaultEquipment = GetDefaultEquipment()
end

---
-- Create teams
-- @hook
-- @internal
-- @realm shared
function GM:CreateTeams()
	team.SetUp(TEAM_TERROR, "Terrorists", Color(0, 200, 0, 255), false)
	team.SetUp(TEAM_SPEC, "Spectators", Color(200, 200, 0, 255), true)

	-- Not that we use this, but feels good
	team.SetSpawnPoint(TEAM_TERROR, "info_player_deathmatch")
	team.SetSpawnPoint(TEAM_SPEC, "info_player_deathmatch")
end

---
-- Kill footsteps on player and client
-- @hook
-- @realm shared
function GM:PlayerFootstep(ply, pos, foot, sound, volume, rf)
	if IsValid(ply) and (ply:Crouching() or ply:GetMaxSpeed() < 150 or ply:IsSpec()) then
		-- do not play anything, just prevent normal sounds from playing
		return true
	end
end

---
-- Predicted move speed changes
-- @hook
-- @realm shared
function GM:Move(ply, mv)
	if not ply:IsTerror() then return end

	local basemul = 1
	local slowed = false

	-- Slow down ironsighters
	local wep = ply:GetActiveWeapon()

	if IsValid(wep) and wep.GetIronsights and wep:GetIronsights() then
		basemul = 120 / 220
		slowed = true
	end

	local refTbl = {1}

	local mul = hook.Call("TTTPlayerSpeedModifier", GAMEMODE, ply, slowed, mv, refTbl) or 1
	mul = basemul * mul * refTbl[1]

	if ply.sprintMultiplier and (ply.sprintProgress or 0) > 0 then
		local sprintMultiplierModifier = {1}

		hook.Run("TTT2PlayerSprintMultiplier", ply, sprintMultiplierModifier)

		mul = mul * ply.sprintMultiplier * sprintMultiplierModifier[1]
	end

	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
	mv:SetMaxSpeed(mv:GetMaxSpeed() * mul)
end

local ttt_playercolors = {
	all = {
		COLOR_WHITE,
		COLOR_BLACK,
		COLOR_GREEN,
		COLOR_DGREEN,
		COLOR_RED,
		COLOR_YELLOW,
		COLOR_LGRAY,
		COLOR_BLUE,
		COLOR_NAVY,
		COLOR_PINK,
		COLOR_OLIVE,
		COLOR_ORANGE
	},
	serious = {
		COLOR_WHITE,
		COLOR_BLACK,
		COLOR_NAVY,
		COLOR_LGRAY,
		COLOR_DGREEN,
		COLOR_OLIVE
	}
}
local ttt_playercolors_all_count = #ttt_playercolors.all
local ttt_playercolors_serious_count = #ttt_playercolors.serious

local colormode = CreateConVar("ttt_playercolor_mode", "1", {FCVAR_NOTIFY, FCVAR_ARCHIVE})

---
-- @hook
-- @register
-- @realm shared
function GM:TTTPlayerColor(model)
	local mode = colormode:GetInt()

	if mode == 1 then
		return ttt_playercolors.serious[math.random(ttt_playercolors_serious_count)]
	elseif mode == 2 then
		return ttt_playercolors.all[math.random(ttt_playercolors_all_count)]
	elseif mode == 3 then
		-- Full randomness
		return Color(math.random(0, 255), math.random(0, 255), math.random(0, 255))
	end

	-- No coloring
	return COLOR_WHITE
end

-- Drowning and such
local tm, ply, plys

---
-- @hook
-- @realm shared
function GM:Tick()
	local client = CLIENT and LocalPlayer()

	if client and not IsValid(client) then return end

	-- three cheers for micro-optimizations
	plys = client and {client} or player.GetAll()

	for i = 1, #plys do
		ply = plys[i]
		tm = ply:Team()

		if tm == TEAM_TERROR and ply:Alive() then
			if ply:WaterLevel() == 3 then -- Drowning
				if SERVER and ply:IsOnFire() then
					ply:Extinguish()
				end

				local drowningTime = ply.drowningTime or 8

				if ply.drowning then
					ply.drowningProgress = math.max(0, (ply.drowning - CurTime()) * (1 / drowningTime))

					if SERVER and ply.drowning < CurTime() then
						local dmginfo = DamageInfo()

						dmginfo:SetDamage(15)
						dmginfo:SetDamageType(DMG_DROWN)
						dmginfo:SetAttacker(game.GetWorld())
						dmginfo:SetInflictor(game.GetWorld())
						dmginfo:SetDamageForce(Vector(0, 0, 1))

						ply:TakeDamageInfo(dmginfo)

						-- have started drowning properly
						ply:StartDrowning(true, 1, drowningTime)
					end
				elseif SERVER then
					ply:StartDrowning(true, drowningTime, drowningTime)
				end
			elseif SERVER then
				ply:StartDrowning(false)
			end

			-- Run DNA Scanner think also when it is not deployed
			if SERVER and IsValid(ply.scanner_weapon) and wep ~= ply.scanner_weapon then
				ply.scanner_weapon:Think()
			end
		elseif SERVER and tm == TEAM_SPEC then
			if ply.propspec then
				PROPSPEC.Recharge(ply)

				if IsValid(ply:GetObserverTarget()) then
					ply:SetPos(ply:GetObserverTarget():GetPos())
				end
			end

			-- if spectators are alive, ie. they picked spectator mode, then
			-- DeathThink doesn't run, so we have to SpecThink here
			if ply:Alive() then
				self:SpectatorThink(ply)
			end
		end
	end

	if CLIENT then
		if client:Alive() and client:Team() ~= TEAM_SPEC then
			WSWITCH:Think()
			RADIO:StoreTarget()
		end

		VOICE.Tick()
	end
end
