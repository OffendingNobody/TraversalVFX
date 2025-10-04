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

export type AnyFunc = (any) -> any -- we create a type function that takes in any and outputs any

local Signal = {} -- Custom signal class for handling events, similar to RBXScriptSignal
Signal.__index = Signal -- point to Signal module. IF self cannot find the key inside of itself, itll fire index and use signal module instead.

function Signal.new()
	-- creates signal class
	local self = setmetatable({}, Signal) -- setmetatable to signal so it gets metamethods
	self._connections = {} -- Store connections
	return self
end

function Signal:Connect(callback : AnyFunc)
	table.insert(self._connections, callback)
	
	local connection = {} -- we return this object so local conn = Signal:Connect(), we can do conn:Disconnect just like roblox :D
	function connection:Disconnect()
		for i, fn in self._connections do -- loop through connections
			if fn == callback then -- check if the connection callback is the same as the callback we put in
				table.remove(self._connections, i) -- if so disconnect it
				break -- stop the loop since we already found the connection
			end
		end
	end
	
	return connection -- return conn so we can do conn:Disconnect later if wanted
end

function Signal:Fire(...) --- ... means you can pass anything into the func 
	for _, callback in self._connections do -- loop through every connection
		task.spawn(callback, ...) -- call the function with the ... params
	end
end


local module = {}
module.__index = module -- point back to module so if self cannot find the method itll point back here

module.Abilities = {} -- save abilities here so we can access through other scripts if wanted

type ConfigsT = { -- params
	MaxBounces : number | "Infinite", -- cannot bounce more than maxbounces, so say max 5, itll hit 6 enemies, if infinite itll keep zapping until it hits every enemy
	MaxDistance : number, -- if enemy is more than this distance it wont be zapped.
	ZapDelay : number, -- the delay between each zap
	ExponentialFactor : number, -- each zap the zap delay gets faster and faster
	EnemiesFolder : Folder, -- specify the zappable enemies
}

function module.CreateAbility(name : string, configs : ConfigsT) -- Create ability class
	local ExistingAbility = module.Abilities[name] -- if class exist we overwrite it
	if ExistingAbility then -- check if ability exists
		local Warning = string.format("%s is already registered, overwriting with new register.", name) -- we warn that [name] already exists and we will be registering another one over it
		warn(Warning) -- warn it
	end
	
	local NewAbility = setmetatable({}, module) -- create class ability
	NewAbility.Config = configs -- save configs
	
	NewAbility.Connections = {} -- save all connections here
	NewAbility._OnChained = Signal.new() -- fires the chain so that the chain starts
	NewAbility._HitByChain = Signal.new() -- whenever a enemy gets zapped inside that chain itll fire from this conn
	NewAbility._HitLast = Signal.new() -- if the enemy was the last enemy in that chain itll fire this conn
	
	return NewAbility -- return the class so we can use it
end

export type CreatedAbility = typeof(module.CreateAbility()) -- this is this ability class type, so if we do ability : CreatedAbility = yadada, itll give back the
-- intellisense so it knows that there is ability.Connections, etc.
-- this function returns the ability from specified name
function module.GrabAbility(name : string) : CreatedAbility -- just for qol ig (so you can use in other scripts i recommend using in one script tho), if it doesnt exist we'll just create it
	local Ability = module.Abilities[name] -- we index ability through name 
	if not Ability then -- if there is no ability
		local Warning = string.format("%s is not registered, overwriting with new register.", name) -- we warn that there is no ability
		warn(Warning) -- warn it
		Ability = module.CreateAbility(name) -- then we create a new ability
		module.Abilities[name] = Ability -- set the module.Abilities[name] to the New Ability
	end
	
	return Ability -- we give the new ability class back.
end

function module.GetClosest(StartPos : Vector3, Folder : Folder) -- returns the closest model to the startpos
	local ClosestModel, ClosestMagnitude = nil, math.huge -- init, nil means no enemies, math.huge so the first enemy found will be the start
	
	for _, model in Folder:GetChildren() do -- loop through the folder specified in func param
		local Magnitude = (model:GetPivot().Position - StartPos).Magnitude -- we check the distance between the StartPosition and the enemy position
		if Magnitude < ClosestMagnitude then -- if the dist is less than the closest dist
			ClosestMagnitude = Magnitude -- set closest dist to this dist
			ClosestModel = model -- then set the model found in this dist
		end
	end
	
	return ClosestModel, ClosestMagnitude -- we give back the closest model and the closest dist.
end 

function module.GetNearby(origin : Vector3, folder : Folder, ignore : {[Model]: boolean}, maxDist : number) -- gets every Model in given Folder based on ignores and if its close enough (aka within max dist)
	local results = {} -- save all nearby found 
	for _, model in ipairs(folder:GetChildren()) do -- loop through folder specified
		if not ignore[model] then -- if it isnt found in the ignore table then
			local dist = (model:GetPivot().Position - origin).Magnitude -- get the dist
			if dist <= maxDist then -- see if its close enough
				table.insert(results, model) -- and add it to the results
			end
		end
	end
	return results -- we then return all the results
end

function module:LinkTo(fn : RBXScriptSignal) -- links firechain to this rbxscriptconn
	table.insert(self.Connections, fn:Connect(function() -- insert the connection so we can disconnect it later
		local ClosestEnemy = module.GetClosest(humroot.Position, self.Config.EnemiesFolder) -- gets the nearest enemy to startpos
		if not ClosestEnemy then return end -- if none then we return
		
		self:FireChain(ClosestEnemy) -- we then fire that enemy through the fire chain conn
	end))
end

function module:Destroy() -- cleanup
	for _, conn in self.Connections do -- disconnect all connections
		conn:Disconnect()
	end
	self._OnChained._connections = {} -- clean up connections that were in the signals
	self._HitByChain._connections = {}
	self._HitLast._connections = {}
end


function module:FireChain(startEnemy : Model) -- just fires the onchained connection
	self._OnChained:Fire(startEnemy)
end

function module:ConnectChained() -- this will keep getting the next nearest enemy in a chained pattern, untill it hits the maxbounces
	self._OnChained:Connect(function(StartEnemy)
		local visited = {} -- construct a table of the ones we already electrified
		local current = StartEnemy -- we set the start current to start enemy

		visited[StartEnemy] = true -- set to visited to true
		
		self._HitByChain:Fire(current) -- hit current 
		
		local BounceCount = 0 -- count how many zaps happened
		local IsBouncing = true -- check if its still bouncing
		
		local delay = self.Config.ZapDelay -- time between each zaps
		
		while IsBouncing do -- runs each delay if isbouncing is true
			task.wait(delay)
			delay *= (self.Config.ExponentialFactor or 1) -- delay gets exponentially faster, example delay = 1, delay *= 0.5 = 0.5 for the next zap.
			
			-- get everything near current
			local Neighbors = module.GetNearby( -- we get everything near SourceA, then we set that to be new sources.
				current:GetPivot().Position, -- start pos
				self.Config.EnemiesFolder, -- enemies to use
				visited, -- ignore any already visited electricifies
				self.Config.MaxDistance -- max distance to be gotten
			)

			if #Neighbors == 0 then -- no more
				self._HitLast:Fire(current) -- fire hit last conn
				break -- no more targets
			end
			
			if self.Config.MaxBounces ~= "Infinite" and BounceCount >= self.Config.MaxBounces then -- if the bounces are not infinite we check if the bounce count is higher than the max bounces and stop the loop if so 
				IsBouncing = false -- set isbouncing false
				return -- exit the function
			end

			-- we sort the neighbors to be the smallest dist to biggest dist
			table.sort(Neighbors, function(a, b) -- I think its fine to do this per loop since its O(log n log)
				local pa = a:GetPivot().Position -- get pos of the a
				local pb = b:GetPivot().Position -- get pos of b
				local cpos = current:GetPivot().Position -- we get pos of current
				return (pa - cpos).Magnitude < (pb - cpos).Magnitude -- we then check if dist between pa and current is less than pb and current then sort that
			end)

			local nextEnemy = Neighbors[1] -- we get the closest dist
			visited[nextEnemy] = true -- make sure we dont visit the same enemy again

			self._HitByChain:Fire(nextEnemy) -- fire hit conn

			current = nextEnemy -- we set the current to the enemy so we can then rerun this loop on the current
			BounceCount += 1 -- up bounce by 1
		end
	end)
end

function module:ListenToLastChain(fn : AnyFunc) --- idk maybe if you wanna put vfx at the last strike
	-- important if you are using this function, it fires like [ZAPINTERVAL] later, since itll loop again
	-- if no neighbors itll fire current one with this, so if I highly suggest not doing dmg for this one since itll repeat,
	-- unless you want to
	self._HitLast:Connect(fn) -- fire the last hit 
end

function module:ListenToChainHit(fn : AnyFunc)
	self._HitByChain:Connect(fn) -- itll call fn every time it gets hit
end

function module.EmitVfx(vfx : ParticleEmitter, amount : number, CleanUp : number)
	vfx:Emit(amount) -- emit particle by amount
	
	task.delay(CleanUp, function() -- cleanup any vfx
		if vfx.Parent:IsA("Attachment") and #vfx.Parent:GetChildren() == 1 then -- if parent is attachment and theres no other particles under the attachment we destroy it
			vfx.Parent:Destroy() -- destroy
			return -- exit function
		end

		if vfx then
			vfx:Destroy() -- then we destroy vfx
		end
	end)
end

-- example tool 
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage.Assets
local Zap = Assets.Zap
local Final = Assets.Final

local QuickTool = backpack.QuickThunder
local QuickThunder = module.CreateAbility(QuickTool, {
	MaxBounces = "Infinite", -- bounce forever 
	MaxDistance = 100, -- if enemy is farther than this dont take them into account
	EnemiesFolder = workspace.Enemys, -- the enemies that can be zapped
	ExponentialFactor = 0.7, -- delay multipler each bounce
	ZapDelay = 0.15, -- base delay between each zap
})

QuickThunder:ConnectChained() -- initialize chained zapping

QuickThunder:ListenToLastChain(function(Enemy : Model) -- fires when the last enemy gets hit
	task.wait(0.8) -- wait 0.8 secs
	warn( -- warn which enemy was the last
		string.format(
			"%s was the last enemy",
			Enemy.Name
		)
	)

	local NewFinal = Final:Clone() -- we clone final vfx
	NewFinal.Parent = Enemy.HumanoidRootPart -- parent it to enemy humroot
	module.EmitVfx(NewFinal.Final, 1, 5) -- emit the vfx with a 1 amount and 5 clean up (destroys after 5 secs)
end)

QuickThunder:ListenToChainHit(function(Enemy : Model) -- fires each time a enemy is zapped
	local enemyhum = Enemy:FindFirstChildWhichIsA("Humanoid") -- find first humanoid of enemy
	if enemyhum then -- check if enemy has a hum
		enemyhum:TakeDamage(15) -- of course client sided, so this is just proof of concept.

		local ZapClone = Zap:Clone() -- clone the vfx
		ZapClone.Parent = Enemy.HumanoidRootPart -- parent it to the enmey humroot
		module.EmitVfx(ZapClone.Zap, 1, 5) -- emit vfx with 1 amount and 5 sec clean up
	end
end)

QuickThunder:LinkTo(QuickTool.Activated) -- activates chain upon tool activated

return module
