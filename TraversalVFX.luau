-- By TheProsDev

--[[
	TraversalVFX
	
	this is just a resuable module for chain effects ngl,
	I originally made it just so I could do lightning vfx that would TRAVERSE from a to b to c.
	This module is pretty much that with clean code
	
]]

local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local humroot : BasePart = char:WaitForChild("HumanoidRootPart")

local backpack = player.Backpack

export type AnyFunc = (any) -> any

local Signal = {} -- just a simple signal implementation, idk how good it is compared to the bigger leagues
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._connections = {} -- Store connections
	return self
end

function Signal:Connect(callback : AnyFunc)
	table.insert(self._connections, callback)
	
	local connection = {} -- we return this object so local conn = Signal:Connect(), we can do conn:Disconnect just like roblox :D
	function connection:Disconnect()
		for i, fn in self._connections do
			if fn == callback then
				table.remove(self._connections, i)
				break
			end
		end
	end
	
	return connection
end

function Signal:Fire(...)
	for _, callback in self._connections do
		task.spawn(callback, ...)
	end
end


local module = {}
module.__index = module

module.Abilities = {}

type ConfigsT = { -- params
	MaxBounces : number | "Infinite",
	MaxDistance : number,
	ZapDelay : number,
	ExponentialFactor : number,
	EnemiesFolder : Folder,
}

function module.CreateAbility(name : string, configs : ConfigsT) -- Create ability class
	local ExistingAbility = module.Abilities[name] -- if class exist we overwrite it
	if ExistingAbility then
		local Warning = string.format("%s is already registered, overwriting with new register.", name)
		warn(Warning)
	end
	
	local NewAbility = setmetatable({}, module)
	NewAbility.Config = configs -- save configs
	
	NewAbility.Connections = {}
	NewAbility._OnChained = Signal.new() -- init conns
	NewAbility._HitByChain = Signal.new()
	NewAbility._HitLast = Signal.new()
	
	return NewAbility
end

export type CreatedAbility = typeof(module.CreateAbility())

function module.GrabAbility(name : string) : CreatedAbility -- just for qol ig (so you can use in other scripts i recommend using in one script tho), if it doesnt exist we'll just create it
	local Ability = module.Abilities[name]
	if not Ability then
		local Warning = string.format("%s is not registered, overwriting with new register.", name)
		warn(Warning)
		Ability = module.CreateAbility(name)
		module.Abilities[name] = Ability
	end
	
	return Ability
end

function module.GetClosest(StartPos : Vector3, Folder : Folder) -- returns the closest model to the startpos
	local ClosestModel, ClosestMagnitude = nil, math.huge
	
	for _, model in Folder:GetChildren() do
		local Magnitude = (model:GetPivot().Position - StartPos).Magnitude
		if Magnitude < ClosestMagnitude then
			ClosestMagnitude = Magnitude
			ClosestModel = model
		end
	end
	
	return ClosestModel, ClosestMagnitude
end

function module.GetNearby(origin : Vector3, folder : Folder, ignore : {[Model]: boolean}, maxDist : number) -- gets every Model in given Folder based on ignores and if its close enough (aka within max dist)
	local results = {}
	for _, model in ipairs(folder:GetChildren()) do
		if not ignore[model] then
			local dist = (model:GetPivot().Position - origin).Magnitude
			if dist <= maxDist then
				table.insert(results, model)
			end
		end
	end
	return results
end

function module:LinkTo(fn : RBXScriptSignal) -- links firechain to this rbxscriptconn
	table.insert(self.Connections, fn:Connect(function()
		print("Activating")
		local ClosestEnemy = module.GetClosest(humroot.Position, self.Config.EnemiesFolder) -- gets the nearest enemy to startpos
		if not ClosestEnemy then return end
		
		self:FireChain(ClosestEnemy)
	end))
end

function module:Destroy() -- cleanup
	for _, conn in self.Connections do
		conn:Disconnect()
	end
	self._OnChained._connections = {} -- clean up connections
	self._HitByChain._connections = {}
	self._HitLast._connections = {}
end


function module:FireChain(startEnemy : Model)
	self._OnChained:Fire(startEnemy)
end

function module:ConnectChained() -- this will keep getting the next nearest enemy in a chained pattern, untill it hits the maxbounces
	self._OnChained:Connect(function(StartEnemy)
		local visited = {} -- construct a table of the ones we already electrified
		local current = StartEnemy

		visited[StartEnemy] = true
		
		self._HitByChain:Fire(current) -- hit current 
		
		local BounceCount = 0
		local IsBouncing = true
		
		local delay = self.Config.ZapDelay
		
		while IsBouncing do
			task.wait(delay)
			delay *= (self.Config.ExponentialFactor or 1)
			
			local newQueue = {}

			local Neighbors = module.GetNearby( -- we get everything near SourceA, then we set that to be new sources.
				current:GetPivot().Position,
				self.Config.EnemiesFolder,
				visited, -- ignore any already visited electricifies
				self.Config.MaxDistance
			)

			if #Neighbors == 0 then -- no more
				self._HitLast:Fire(current) -- fire hit last conn
				break -- no more targets
			end
			
			if self.Config.MaxBounces ~= "Infinite" and BounceCount >= self.Config.MaxBounces then
				return
			end

			-- pick the nearest one
			table.sort(Neighbors, function(a, b) -- I think its fine to do this per loop since its O(log n log)
				local pa = a:GetPivot().Position
				local pb = b:GetPivot().Position
				local cpos = current:GetPivot().Position
				return (pa - cpos).Magnitude < (pb - cpos).Magnitude
			end)

			local nextEnemy = Neighbors[1]
			visited[nextEnemy] = true -- make sure we dont visit the same enemy again

			self._HitByChain:Fire(nextEnemy) -- fire hit conn

			current = nextEnemy
			BounceCount += 1			
		end
	end)
end

function module:ListenToLastChain(fn : AnyFunc) --- idk maybe if you wanna put vfx at the last strike
	-- important if you are using this function, it fires like [ZAPINTERVAL] later, since itll loop again
	-- if no neighbors itll fire current one with this, so if I highly suggest not doing dmg for this one since itll repeat,
	-- unless you want to
	self._HitLast:Connect(fn)
end

function module:ListenToChainHit(fn : AnyFunc)
	self._HitByChain:Connect(fn)
end

function module.EmitVfx(vfx : ParticleEmitter, amount : number, CleanUp : number)
	vfx:Emit(amount)
	
	task.delay(CleanUp, function() -- cleanup any vfx
		if vfx.Parent:IsA("Attachment") and #vfx.Parent:GetChildren() == 1 then
			vfx.Parent:Destroy()
			return	
		end
		
		vfx:Destroy()
	end)
end

-- example tool 
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage.Assets
local Zap = Assets.Zap
local Final = Assets.Final

local QuickTool = backpack.QuickThunder
local QuickThunder = module.CreateAbility(QuickTool, {
	MaxBounces = "Infinite",	
	MaxDistance = 100,
	EnemiesFolder = workspace.Enemys,
	ExponentialFactor = 0.7, -- delay multipler each bounce
	ZapDelay = 0.15, -- base delay
})

QuickThunder:ConnectChained()

QuickThunder:ListenToLastChain(function(Enemy : Model)
	task.wait(0.8)
	warn(
		string.format(
			"%s was the last enemy",
			Enemy.Name
		)
	)

	local NewFinal = Final:Clone()
	NewFinal.Parent = Enemy.HumanoidRootPart
	module.EmitVfx(NewFinal.Final, 1, 5)
end)

QuickThunder:ListenToChainHit(function(Enemy : Model)
	local enemyhum = Enemy:FindFirstChildWhichIsA("Humanoid")
	if enemyhum then
		enemyhum:TakeDamage(15) -- of course client sided, so this is just proof of concept.

		local ZapClone = Zap:Clone()
		ZapClone.Parent = Enemy.HumanoidRootPart
		module.EmitVfx(ZapClone.Zap, 1, 5)
	end
end)

QuickThunder:LinkTo(QuickTool.Activated) -- activates chain upon tool activated

return module
