-- VIPKING 2.1 | Ride a Pet egg collector
-- Client-side replacement for vipking.lua. No downloaded code or guessed remotes.
-- RightControl: show/hide. F6: stop all actions. Use X to unload completely.
-- First migration from the old script: rejoin once to remove its unmanaged loops.
-- Live-game compatibility is not guaranteed: server validation still applies.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "VIPKING must run on the client")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
assert(PlayerGui, "VIPKING: PlayerGui was not ready; try again")

local Config = {
    ScanInterval = 15, -- recovery scan; normal discovery uses instance events
    Tick = 0.12,
    MaxRows = 40,
    MaxManualQueue = 32,
    MaxAttempts = 2,
    RetryBase = 4,
    RetryMax = 30,
    HomeSettle = 0.3, -- brief delivery/replication window, then continue farming
    MaxESP = 80,
    MaxHighlights = 24,
    MaxVolcanoAreas = 8,
    VolcanoCFrame = nil, -- optional exact destination for your map
    ExtraAdminUserIds = {},
    AdminMinGroupRank = 200,
    -- Exact ancestor words; "Baseplate" and "Database" are not gardens.
    GardenWords = {garden = true, gardens = true, plot = true, plots = true,
        farm = true, farms = true, base = true, bases = true},
}

local EggPriority = {
    ["Giant Egg"] = 1000, ["Dragon Egg"] = 990, ["Volcanic Egg"] = 985,
    ["Solaris Egg"] = 980, ["Cherub Egg"] = 970, ["Blackhole Egg"] = 960,
    ["Galaxy Egg"] = 950, ["Aurora Egg"] = 940, ["Soul Egg"] = 930,
    ["Sinister Egg"] = 920, ["Flaming Egg"] = 910, ["Dominus Egg"] = 900,
    ["Asteroid Egg"] = 890, ["Skull Egg"] = 880, ["Crystal Egg"] = 870,
    ["Diamond Egg"] = 860, ["Golden Egg"] = 850, ["Glass Egg"] = 840,
    ["Ice Egg"] = 830, ["Slime Egg"] = 820, ["Flower Egg"] = 810,
    ["Mushroom Egg"] = 800, ["Leaf Egg"] = 790, ["Stone Egg"] = 780,
    ["Easter Egg"] = 770, ["Cracked Egg"] = 760, ["Brown Egg"] = 750,
    ["White Egg"] = 740,
}

-- Pure scheduling rules are separated for regression tests.
-- CORE_BEGIN
local Rules = {}
function Rules.eggName(name)
    local lower = string.lower(name)
    return EggPriority[name] ~= nil or string.find(lower, "%f[%a]egg%f[%A]") ~= nil
end
function Rules.gardenName(name)
    local split = string.gsub(name, "(%l)(%u)", "%1 %2")
    for word in string.gmatch(string.lower(split), "%a+") do
        if Config.GardenWords[word] then return true end
    end
    return false
end
function Rules.less(a, b, mode)
    if mode == "Nearest" and a.distance ~= b.distance then return a.distance < b.distance end
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end
function Rules.retryDelay(failures)
    return math.min(Config.RetryMax, Config.RetryBase * 2 ^ math.min(failures - 1, 8))
end
function Rules.autoAllowed(mode, selected, name)
    return mode == "All" or selected[name] == true
end
function Rules.volcanoName(name)
    local lower = string.lower(name)
    return string.find(lower, "volcano", 1, true) ~= nil or string.find(lower, "volcanic", 1, true) ~= nil
end
function Rules.travelMarker(name)
    local lower = string.lower(name)
    for _, word in ipairs({"spawn", "arrival", "entrance", "entry", "teleport", "portal", "checkpoint"}) do
        if string.find(lower, word, 1, true) then return true end
    end
    return string.match(lower, "^tp") ~= nil or string.match(lower, "tp$") ~= nil
end
function Rules.hazardName(name)
    local lower = string.lower(name)
    for _, word in ipairs({"lava", "kill", "damage", "acid", "death"}) do
        if string.find(lower, word, 1, true) then return true end
    end
    return false
end
-- CORE_END

local App = {
    alive = true, epoch = 0, connections = {}, candidates = {}, nextId = 0,
    queue = {}, queued = {}, active = nil, holding = nil,
    cooldown = setmetatable({}, {__mode = "k"}),
    auto = false, selected = {}, sort = "Priority", mode = "All",
    speed = "Balanced", autoReturn = true, stowEggTools = true,
    antiAFK = false, autoLeave = false, theme = "Galaxy", language = "en",
    uiScale = 1, home = nil, homeCharacter = nil, tab = "Collect",
    minimized = false, picked = 0, unverified = 0, failures = 0,
    started = os.clock(), status = "Ready", logs = {}, ui = {}, dirty = true,
    search = "", espEnabled = false, espSelectedOnly = false, espRows = {}, espCount = 0,
    volcanoSaved = nil, volcanoInfo = "Auto-detect from loaded map, or save your position at the volcano.",
}
local Profiles = {
    Fast = {settle = 0.05, grace = 0.55, gap = 0.05},
    Balanced = {settle = 0.12, grace = 1.0, gap = 0.12},
    Reliable = {settle = 0.25, grace = 1.8, gap = 0.25},
}
local Compat = {firePrompt = type(fireproximityprompt) == "function" and fireproximityprompt or nil}
pcall(function() Compat.virtualUser = game:GetService("VirtualUser") end)

function App:connect(signal, callback)
    local connection = signal:Connect(function(...)
        if self.alive then callback(...) end
    end)
    table.insert(self.connections, connection)
    return connection
end
function App:log(message)
    self.status = message
    table.insert(self.logs, 1, string.format("%02d:%02d  %s",
        math.floor((os.clock() - self.started) / 60), math.floor(os.clock() - self.started) % 60, message))
    if #self.logs > 60 then table.remove(self.logs) end
    self.dirty = true
end
function App:character()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then return char, root, humanoid end
    return nil
end
function App:valid(token, char)
    return self.alive and token == self.epoch and self:character() == char
end
function App:waitFor(seconds, token, char)
    local untilTime = os.clock() + seconds
    repeat
        if not self:valid(token, char) then return false end
        task.wait(math.min(0.05, math.max(0, untilTime - os.clock())))
    until os.clock() >= untilTime
    return self:valid(token, char)
end
function App:releaseInput()
    local holding = self.holding
    self.holding = nil
    if holding then
        pcall(function() holding.prompt:InputHoldEnd() end)
        if holding.originalHold ~= nil then
            pcall(function() holding.prompt.HoldDuration = holding.originalHold end)
        end
    end
end
function App:cancel(message)
    self.epoch = self.epoch + 1
    self.queue, self.queued = {}, {}
    self:releaseInput()
    if message then self:log(message) end
end
function App:stop(message)
    self.auto = false
    self:cancel(message or "Stopped")
end
function App:unload()
    if not self.alive then return end
    self:stop()
    self.alive = false
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.connections = {}
    self:clearESP()
    if self.espGuiFolder then self.espGuiFolder:Destroy() end
    if self.espWorldFolder then self.espWorldFolder:Destroy() end
    if self.gui then self.gui:Destroy() end
end

-- Cooperative singleton: a new v2 run fully unloads an older v2 session.
do
    local previous = PlayerGui:FindFirstChild("VIPKING_V2")
    if previous then
        local shutdown = previous:FindFirstChild("Shutdown")
        if shutdown and shutdown:IsA("BindableFunction") then pcall(function() shutdown:Invoke() end) end
        previous:Destroy()
    end
end

function App:isOwned(obj)
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    return (char and obj:IsDescendantOf(char)) or (backpack and obj:IsDescendantOf(backpack)) or false
end
function App:inventory()
    -- Deduplicate by the top-level carried item, not every egg-named descendant.
    local items, seen = {}, {}
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetDescendants()) do
            if (item:IsA("Tool") or item:IsA("Model") or item:IsA("BasePart")) and Rules.eggName(item.Name) then
                local top = item
                while top.Parent and top.Parent ~= container do top = top.Parent end
                if top.Parent == container and not top:IsA("Accessory")
                    and top.Name ~= "HumanoidRootPart" and not seen[top] then
                    seen[top] = true
                    table.insert(items, {object = top, name = item.Name, priority = EggPriority[item.Name] or 1})
                end
            end
        end
    end
    scan(LocalPlayer.Character)
    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    table.sort(items, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.name < b.name
    end)
    return items
end
function App:confirmed(egg, name, before)
    if egg.Parent and self:isOwned(egg) then return true end
    for _, item in ipairs(self:inventory()) do
        if item.name == name and not before[item.object] then return true end
    end
    return false
end
function App:position(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") and obj:FindFirstChildWhichIsA("BasePart", true) then return obj:GetPivot().Position end
    return nil
end
function App:eligible(obj)
    if not obj.Parent or not obj:IsDescendantOf(Workspace) then return false end
    if not (obj:IsA("Model") or obj:IsA("BasePart")) or not Rules.eggName(obj.Name) then return false end
    local node = obj
    while node and node ~= Workspace do
        if node:IsA("Tool") or node:IsA("Accessory") then return false end
        if node:IsA("Model") or node:IsA("Folder") then
            if Rules.gardenName(node.Name) then return false end
        end
        if node:IsA("Model") and (Players:GetPlayerFromCharacter(node) or node:FindFirstChildOfClass("Humanoid")) then
            return false
        end
        if node ~= obj and node:IsA("Model") and Rules.eggName(node.Name) then return false end
        node = node.Parent
    end
    return self:position(obj) ~= nil
end
function App:track(obj)
    if not self.candidates[obj] and (obj:IsA("Model") or obj:IsA("BasePart")) and Rules.eggName(obj.Name) then
        self.nextId = self.nextId + 1
        self.candidates[obj] = self.nextId
        self.dirty = true
    end
end
function App:scan()
    for obj in pairs(self.candidates) do
        if not obj:IsDescendantOf(Workspace) then self.candidates[obj] = nil end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do self:track(obj) end
    self.dirty = true
end
function App:listEggs()
    local _, root = self:character()
    local list = {}
    for obj, id in pairs(self.candidates) do
        if self:eligible(obj) then
            table.insert(list, {object = obj, name = obj.Name, id = id, priority = EggPriority[obj.Name] or 1,
                distance = root and (self:position(obj) - root.Position).Magnitude or math.huge})
        end
    end
    table.sort(list, function(a, b) return Rules.less(a, b, self.sort) end)
    return list
end
function App:findPrompt(egg)
    -- Only prompts belonging to this egg. Never trigger a nearby unrelated prompt.
    local center = self:position(egg)
    if not center then return nil end
    local best, bestDistance
    for _, child in ipairs(egg:GetDescendants()) do
        if child:IsA("ProximityPrompt") and child.Enabled then
            local pos = self:position(child.Parent)
            local distance = pos and (pos - center).Magnitude
            if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = child, distance end
        end
    end
    return best
end
function App:move(root, cf)
    if root.Anchored then return false end
    root.CFrame = cf
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end
function App:saveHome()
    local char, root = self:character()
    if not root then self:log("Wait for your character to spawn"); return end
    if self.active then self:log("Stop the current action before saving home"); return end
    self.home, self.homeCharacter = root.CFrame, char
    self:log("Return point saved")
end
function App:queueJob(job)
    if not self.alive then return end
    if job.kind ~= "pickup" and job.kind ~= "home" and job.kind ~= "volcano" then return end
    if #self.queue >= Config.MaxManualQueue then self:log("Queue is full"); return end
    if job.egg and (self.queued[job.egg] or (self.active and self.active.egg == job.egg)) then return end
    if job.egg then self.queued[job.egg] = true end
    table.insert(self.queue, job)
    self.dirty = true
end
function App:nextJob()
    while #self.queue > 0 do
        local job = table.remove(self.queue, 1)
        if job.egg then self.queued[job.egg] = nil end
        if not job.egg or self:eligible(job.egg) then return job end
    end
    if not self.auto then return nil end
    -- A carried/equipped egg must not block the next farm trip.
    for _, entry in ipairs(self:listEggs()) do
        local retry = self.cooldown[entry.object]
        if (not retry or retry.at <= os.clock()) and Rules.autoAllowed(self.mode, self.selected, entry.name) then
            return {kind = "pickup", egg = entry.object, automatic = true}
        end
    end
    self.status = self.mode == "Selected" and "Waiting for selected egg types" or "Waiting for available eggs"
    return nil
end

function App:attemptPickup(egg, token, char, root, before, name)
    local prompt = self:findPrompt(egg)
    if not prompt then return "failed", "No enabled prompt inside " .. name end
    local pos = self:position(prompt.Parent)
    if not pos then return "failed", "Prompt has no usable position" end
    if prompt.MaxActivationDistance < 0.5 then return "failed", "Prompt activation distance is too small" end
    local offset = math.min(2, prompt.MaxActivationDistance * 0.5)
    if not self:move(root, CFrame.new(pos + Vector3.new(0, offset, 0))) then return "failed", "Character is anchored" end
    local profile = Profiles[self.speed]
    if not self:waitFor(profile.settle, token, char) then return "cancelled" end
    if self:confirmed(egg, name, before) then return "confirmed" end
    if not self:eligible(egg) then return "unverified", "Egg moved or disappeared before pickup" end
    if not prompt.Parent or not prompt.Enabled then return "failed", "Prompt became unavailable" end
    if (root.Position - pos).Magnitude > prompt.MaxActivationDistance then return "failed", "Server moved character out of range" end

    local originalHold = prompt.HoldDuration
    self.holding = {prompt = prompt, originalHold = originalHold}
    -- One accelerated attempt, then the prompt's normal hold. Never spam prompts.
    if Compat.firePrompt and self.speed ~= "Reliable" then
        local ok = pcall(function()
            prompt.HoldDuration = 0
            Compat.firePrompt(prompt)
        end)
        pcall(function() prompt.HoldDuration = originalHold end)
        if ok then
            local deadline = os.clock() + profile.grace
            repeat
                if not self:valid(token, char) then return "cancelled" end
                if self:confirmed(egg, name, before) then return "confirmed" end
                task.wait(0.05)
            until os.clock() >= deadline
        end
    end
    if not self:valid(token, char) then return "cancelled" end
    if self:confirmed(egg, name, before) then return "confirmed" end
    if not self:eligible(egg) then return "unverified", "Egg left the map; ownership not confirmed" end
    if not prompt.Parent or not prompt.Enabled then return "failed", "Prompt disabled before normal hold" end
    if originalHold > 15 then return "failed", "Prompt hold exceeds the 15-second limit" end

    local held = pcall(function() prompt:InputHoldBegin() end)
    if not held then return "failed", "Prompt input is unavailable in this client" end
    local holdUntil = os.clock() + originalHold + 0.08
    repeat
        if not self:valid(token, char) then return "cancelled" end
        if self:confirmed(egg, name, before) then return "confirmed" end
        task.wait(0.05)
    until os.clock() >= holdUntil
    self:releaseInput()
    local deadline = os.clock() + profile.grace
    repeat
        if not self:valid(token, char) then return "cancelled" end
        if self:confirmed(egg, name, before) then return "confirmed" end
        task.wait(0.05)
    until os.clock() >= deadline
    if not self:eligible(egg) then return "unverified", "Egg left the map; ownership not confirmed" end
    return "failed", "No inventory confirmation for " .. name
end

function App:pickup(job, token, char, root)
    local egg, before = job.egg, {}
    if not self:eligible(egg) then return end
    local name = egg.Name
    for _, item in ipairs(self:inventory()) do before[item.object] = true end
    local result, reason
    for attempt = 1, Config.MaxAttempts do
        if not self:valid(token, char) then return end
        self.status = string.format("Picking up %s (%d/%d)", name, attempt, Config.MaxAttempts)
        result, reason = self:attemptPickup(egg, token, char, root, before, name)
        self:releaseInput()
        if result ~= "failed" then break end
        if not self:waitFor(Profiles[self.speed].gap, token, char) then return end
    end
    if not self:valid(token, char) or result == "cancelled" then return end
    if result == "confirmed" then
        self.picked = self.picked + 1
        self.cooldown[egg] = nil
        self:log("Confirmed pickup: " .. name)
    elseif result == "unverified" then
        self.unverified = self.unverified + 1
        self.cooldown[egg] = {at = os.clock() + Config.RetryMax, failures = 1}
        self:log(reason or "Pickup could not be verified")
    else
        self.failures = self.failures + 1
        local old = self.cooldown[egg]
        local failures = (old and old.failures or 0) + 1
        local delay = Rules.retryDelay(failures)
        self.cooldown[egg] = {at = os.clock() + delay, failures = failures}
        self:log((reason or "Pickup failed") .. string.format("; retry in %ds", delay))
    end
end

function App:returnSettle(token, char, humanoid)
    if not self:waitFor(Config.HomeSettle, token, char) then return end
    if self.stowEggTools then
        -- Only call UnequipTools when an egg Tool is equipped. No drop or trade input.
        for _, entry in ipairs(self:inventory()) do
            if entry.object:IsA("Tool") and entry.object:IsDescendantOf(char) then
                pcall(function() humanoid:UnequipTools() end)
                break
            end
        end
    end
    -- Non-Tool carried models are left alone; the scheduler still continues.
end

function App:worldObjectAllowed(obj)
    local node = obj
    while node and node ~= Workspace do
        if node:IsA("Tool") or node:IsA("Accessory") or string.find(string.lower(node.Name), "egg", 1, true) then return false end
        if node:IsA("Model") and (Players:GetPlayerFromCharacter(node) or node:FindFirstChildOfClass("Humanoid")) then return false end
        node = node.Parent
    end
    return node == Workspace
end
function App:isHazard(obj)
    local node = obj
    while node and node ~= Workspace do
        if Rules.hazardName(node.Name) then return true end
        node = node.Parent
    end
    return false
end
function App:volcanoObjects()
    local markers, areas = {}, {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and self:worldObjectAllowed(obj) then
            local hasVolcano, node = false, obj
            while node and node ~= Workspace do
                if Rules.volcanoName(node.Name) then hasVolcano = true; break end
                node = node.Parent
            end
            if hasVolcano and obj:IsA("BasePart") and obj.Anchored and not self:isHazard(obj)
                and Rules.travelMarker(obj.Name) then
                table.insert(markers, obj)
            elseif Rules.volcanoName(obj.Name) and self:position(obj) then
                table.insert(areas, obj)
            end
        end
    end
    -- Stable ordering; marker search is restricted to volcano-related objects.
    local function order(a, b) return a:GetFullName() < b:GetFullName() end
    table.sort(markers, order); table.sort(areas, order)
    return markers, areas
end
function App:groundAt(position, height, depth)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LocalPlayer.Character and {LocalPlayer.Character} or {}
    params.RespectCanCollide = true
    params.IgnoreWater = false
    local hit = Workspace:Raycast(position + Vector3.new(0, height, 0), Vector3.new(0, -depth, 0), params)
    if not hit or hit.Normal.Y < 0.7 or hit.Material == Enum.Material.Water then return nil end
    if not self:worldObjectAllowed(hit.Instance) or self:isHazard(hit.Instance) then return nil end
    if hit.Instance:IsA("BasePart") and (not hit.Instance.Anchored or not hit.Instance.CanCollide) then return nil end
    return CFrame.new(hit.Position + Vector3.new(0, 3.5, 0))
end
function App:resolveVolcano(root)
    if self.volcanoSaved then return self.volcanoSaved, "saved position" end
    if Config.VolcanoCFrame then return Config.VolcanoCFrame, "configured position" end
    local markers, areas = self:volcanoObjects()
    for _, marker in ipairs(markers) do
        local destination = self:groundAt(marker.Position, math.max(marker.Size.Y / 2 + 8, 12), 400)
        if destination then return destination, marker:GetFullName() end
    end
    -- A model pivot can be in the crater: sample ground outside its footprint.
    local best, bestDistance, source
    for areaIndex, area in ipairs(areas) do
        if areaIndex > Config.MaxVolcanoAreas then break end
        local box, size
        if area:IsA("Model") then box, size = area:GetBoundingBox()
        else box, size = area.CFrame, area.Size end
        local radius = math.sqrt(size.X * size.X + size.Z * size.Z) / 2 + 14
        for i = 0, 7 do
            local angle = i * math.pi / 4
            local probe = box.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            local destination = self:groundAt(probe, size.Y / 2 + 100, size.Y + 600)
            if destination then
                local distance = (destination.Position - root.Position).Magnitude
                if not bestDistance or distance < bestDistance then
                    best, bestDistance, source = destination, distance, area:GetFullName() .. " (edge)"
                end
            end
        end
        if best then break end
    end
    return best, source
end
function App:teleportVolcano(token, char, root)
    local destination, source = self:resolveVolcano(root)
    if not self:valid(token, char) then return end
    if not destination then
        self.volcanoInfo = "No usable volcano point found. Visit the volcano and press Save volcano point."
        self:log(self.volcanoInfo)
        return
    end
    if self:move(root, destination) then
        self.volcanoInfo = "Destination: " .. source
        self:log("Teleported to volcano: " .. source .. ". Auto farm is stopped.")
    else self:log("Volcano teleport could not move the character") end
end
function App:saveVolcano()
    local _, root = self:character()
    if not root then self:log("Wait for your character to spawn"); return end
    if self.auto or self.active or #self.queue > 0 then self:log("Stop collection before saving the volcano point"); return end
    self.volcanoSaved = root.CFrame
    self.volcanoInfo = "Saved volcano point for this session."
    self:log(self.volcanoInfo)
end

function App:runJob(job)
    local char, root, humanoid = self:character()
    if not root then self:log("Waiting for character"); return end
    if root.Anchored or humanoid.Sit then self:log("Stand up and wait until your character can move"); return end
    local token, start = self.epoch, root.CFrame
    local destination = self.homeCharacter == char and self.home or start
    self.active = job
    local ok, err = xpcall(function()
        if job.kind == "pickup" then self:pickup(job, token, char, root)
        elseif job.kind == "volcano" then self:teleportVolcano(token, char, root)
        elseif job.kind == "home" then
            if self.home and self.homeCharacter == char then self:move(root, self.home); self:log("Returned home")
            else self:log("Save a return point first") end
        end
    end, function(message) return tostring(message) end)
    self:releaseInput() -- finally: always release input and restore prompt properties
    if self:valid(token, char) and job.kind == "pickup" and self.autoReturn then
        local returned, moved = pcall(function() return self:move(root, destination) end)
        if returned and moved then
            local settled, settleError = pcall(function() self:returnSettle(token, char, humanoid) end)
            if not settled and self.alive then self:log("Home cleanup skipped: " .. tostring(settleError)) end
        elseif self.alive then self:log("Return failed; collection remains enabled") end
    end
    self.active = nil
    self.dirty = true
    if not ok and self.alive then
        self:log("Action error: " .. tostring(err))
        if job.egg then self.cooldown[job.egg] = {at = os.clock() + Config.RetryMax, failures = 1} end
    end
end

-- UI: lightweight, touch-friendly, and scaled to the current viewport.
local Palettes = {
    Galaxy = {accent = Color3.fromRGB(141, 112, 255), bg = Color3.fromRGB(18, 20, 31)},
    Ocean = {accent = Color3.fromRGB(71, 177, 255), bg = Color3.fromRGB(15, 25, 36)},
    Emerald = {accent = Color3.fromRGB(74, 218, 163), bg = Color3.fromRGB(16, 29, 27)},
    Nebula = {accent = Color3.fromRGB(239, 119, 195), bg = Color3.fromRGB(29, 20, 33)},
    Crimson = {accent = Color3.fromRGB(255, 119, 131), bg = Color3.fromRGB(32, 20, 26)},
    Purple = {accent = Color3.fromRGB(194, 138, 255), bg = Color3.fromRGB(26, 20, 36)},
}
local Khmer = {
    Collect = "ប្រមូល", World = "ផែនទី", Settings = "ការកំណត់", Activity = "សកម្មភាព",
    Available = "ពងមាន", Confirmed = "បានយក", Queue = "ជួរ", Session = "រយៈពេល",
    ["START AUTO"] = "ចាប់ផ្តើមស្វ័យប្រវត្តិ", ["STOP AUTO"] = "បញ្ឈប់ស្វ័យប្រវត្តិ",
    ["Pick next"] = "យកពងបន្ទាប់", ["Save home"] = "រក្សាទីតាំង", ["Go home"] = "ត្រឡប់ទីតាំង",
    ["Search eggs..."] = "ស្វែងរកពង...",
    ["No eggs match your search"] = "គ្មានពងត្រូវនឹងការស្វែងរក",
    ["No eligible eggs in the loaded map"] = "មិនមានពងនៅលើផែនទីដែលបានផ្ទុក",
    ["Return after pickup"] = "ត្រឡប់ក្រោយយកពង", ["Stow egg tools at home"] = "ទុកពងនៅក្នុងកាបូប",
    ["Anti-AFK"] = "ការពារនៅស្ងៀម", ["Auto leave for owner/admin"] = "ចេញពេលម្ចាស់ចូល",
    ["Refresh map"] = "ផ្ទុកផែនទីឡើងវិញ", ["Clear retry cooldowns"] = "សម្អាតពេលរង់ចាំ",
    ["Clear selected types"] = "សម្អាតប្រភេទដែលជ្រើស", ["Reset session stats"] = "កំណត់ស្ថិតិឡើងវិញ",
    ["Clear activity"] = "សម្អាតសកម្មភាព", ["Unload VIPKING"] = "បិទ VIPKING",
    PICK = "យក", ON = "បើក", OFF = "បិទ", Selected = "បានជ្រើស", All = "ទាំងអស់",
    Priority = "លំដាប់", Nearest = "ជិតបំផុត", ["Auto types"] = "ប្រភេទស្វ័យប្រវត្តិ",
    Speed = "ល្បឿន", Theme = "ពណ៌", ["UI scale"] = "ទំហំ", Language = "ភាសា",
    ["Egg ESP"] = "បង្ហាញពង ESP", ["ESP selected types only"] = "បង្ហាញតែប្រភេទដែលជ្រើស",
    ["TP to volcano"] = "ទៅភ្នំភ្លើង", ["Save volcano point"] = "រក្សាទីតាំងភ្នំភ្លើង",
    ["Use auto-detection"] = "ស្វែងរកទីតាំងស្វ័យប្រវត្តិ",
}
function App:tr(key) return self.language == "km" and Khmer[key] or key end
function App:colors()
    local palette = Palettes[self.theme]
    return {accent = palette.accent, bg = palette.bg, card = palette.bg:Lerp(Color3.new(1, 1, 1), 0.055),
        button = palette.bg:Lerp(Color3.new(1, 1, 1), 0.10), border = palette.bg:Lerp(Color3.new(1, 1, 1), 0.14),
        text = Color3.fromRGB(237, 240, 249), muted = Color3.fromRGB(155, 163, 185),
        danger = Color3.fromRGB(251, 112, 131), ink = Color3.fromRGB(17, 20, 30)}
end
function App:node(class, parent, props)
    local obj = Instance.new(class)
    for property, value in pairs(props or {}) do obj[property] = value end
    obj.Parent = parent
    return obj
end
function App:paint(obj, property, role)
    obj:SetAttribute("Color_" .. property, role)
    obj[property] = self:colors()[role]
end
function App:round(obj, radius)
    self:node("UICorner", obj, {CornerRadius = UDim.new(0, radius or 10)})
end
function App:label(parent, value, size, position, fontSize, role)
    local label = self:node("TextLabel", parent, {BackgroundTransparency = 1, Text = value,
        Size = size, Position = position or UDim2.new(), TextSize = fontSize or 13,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd})
    self:paint(label, "TextColor3", role or "text")
    return label
end
function App:keyText(obj, key, property)
    property = property or "Text"
    obj:SetAttribute("Key_" .. property, key)
    obj[property] = self:tr(key)
end
function App:button(parent, title, size, position, callback, primary)
    local button = self:node("TextButton", parent, {Size = size, Position = position or UDim2.new(),
        Text = title, Font = Enum.Font.GothamMedium, TextSize = 13,
        BorderSizePixel = 0, AutoButtonColor = true, TextTruncate = Enum.TextTruncate.AtEnd})
    self:paint(button, "BackgroundColor3", primary and "accent" or "button")
    self:paint(button, "TextColor3", primary and "ink" or "text")
    self:round(button, 9)
    if callback then
        button.Activated:Connect(function()
            if not self.alive then return end
            local ok, err = pcall(callback)
            if not ok then self:log("Control error: " .. tostring(err)) end
            self.dirty = true
        end)
    end
    return button
end
function App:textBox(parent, placeholder, size, position)
    local box = self:node("TextBox", parent, {Size = size, Position = position, Text = "", ClearTextOnFocus = false,
        BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left})
    self:paint(box, "BackgroundColor3", "card")
    self:paint(box, "TextColor3", "text")
    self:paint(box, "PlaceholderColor3", "muted")
    self:keyText(box, placeholder, "PlaceholderText")
    self:node("UIPadding", box, {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8)})
    self:round(box)
    return box
end
function App:scroll(parent, size, position)
    local scroll = self:node("ScrollingFrame", parent, {Size = size, Position = position or UDim2.new(),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y})
    self:paint(scroll, "ScrollBarImageColor3", "accent")
    self:node("UIListLayout", scroll, {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    self:node("UIPadding", scroll, {PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8)})
    return scroll
end
function App:refreshStyle()
    local colors = self:colors()
    for _, obj in ipairs(self.gui:GetDescendants()) do
        for name, value in pairs(obj:GetAttributes()) do
            if string.sub(name, 1, 6) == "Color_" then obj[string.sub(name, 7)] = colors[value]
            elseif string.sub(name, 1, 4) == "Key_" then obj[string.sub(name, 5)] = self:tr(value) end
        end
    end
    self.dirty = true
end
function App:fit()
    if not self.ui.screen then return end
    local size = self.ui.screen.AbsoluteSize
    local scale = math.max(0.25, math.min(self.uiScale, (size.X - 20) / 448, (size.Y - 20) / 650))
    self.ui.scale.Scale = scale
    local w, h = 448 * scale, (self.minimized and 72 or 650) * scale
    local position = self.ui.main.Position
    self.ui.main.Position = UDim2.fromOffset(
        math.clamp(position.X.Offset, 0, math.max(0, size.X - w)),
        math.clamp(position.Y.Offset, 0, math.max(0, size.Y - h)))
end
function App:showTab(tab)
    self.tab = tab
    for name, page in pairs(self.ui.pages) do page.Visible = name == tab end
    for name, button in pairs(self.ui.tabs) do
        self:paint(button, "BackgroundColor3", name == tab and "accent" or "button")
        self:paint(button, "TextColor3", name == tab and "ink" or "text")
    end
    self.dirty = true
end
function App:toggleVisible()
    self.ui.main.Visible = not self.ui.main.Visible
    self.ui.launcher.Visible = not self.ui.main.Visible
end
function App:toggleAuto()
    if self.auto then self:stop("Auto collection stopped")
    else
        if self.active and self.active.kind == "volcano" then self:log("Wait for the volcano teleport to finish"); return end
        for _, job in ipairs(self.queue) do
            if job.kind == "volcano" then self:log("Wait for the volcano teleport to finish"); return end
        end
        self.auto = true
        self:log(self.mode == "Selected" and "Auto started for selected types" or "Auto started for all eligible eggs")
    end
end

function App:buildCollect(page)
    self.ui.stats = {}
    for i, key in ipairs({"Available", "Confirmed", "Queue", "Session"}) do
        local card = self:node("Frame", page, {Size = UDim2.new(0.25, -6, 0, 62),
            Position = UDim2.new((i - 1) * 0.25, 0, 0, 0), BorderSizePixel = 0})
        self:paint(card, "BackgroundColor3", "card"); self:round(card)
        local value = self:label(card, "0", UDim2.new(1, -16, 0, 27), UDim2.fromOffset(10, 7), 20)
        value.Font = Enum.Font.GothamBold
        local caption = self:label(card, "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(10, 37), 10, "muted")
        self:keyText(caption, key)
        self.ui.stats[key] = value
    end
    self.ui.farm = self:button(page, "", UDim2.new(1, 0, 0, 42), UDim2.fromOffset(0, 74), function() self:toggleAuto() end, true)
    local actions = {
        {"Pick next", function()
            local list = self:listEggs()
            for _, entry in ipairs(list) do
                if not self.queued[entry.object] and not (self.active and self.active.egg == entry.object) then
                    self:queueJob({kind = "pickup", egg = entry.object}); return
                end
            end
            self:log("No available egg to queue")
        end},
        {"Save home", function() self:saveHome() end},
        {"Go home", function() self:stop("Returning home"); self:queueJob({kind = "home"}) end},
    }
    for i, info in ipairs(actions) do
        local button = self:button(page, "", UDim2.new(1 / 3, -5, 0, 36), UDim2.new((i - 1) / 3, 0, 0, 124), info[2])
        self:keyText(button, info[1])
    end
    self.ui.search = self:textBox(page, "Search eggs...", UDim2.new(0.65, -6, 0, 36), UDim2.fromOffset(0, 172))
    self.ui.sort = self:button(page, "", UDim2.new(0.35, 0, 0, 36), UDim2.new(0.65, 0, 0, 172), function()
        self.sort = self.sort == "Priority" and "Nearest" or "Priority"
    end)
    self:connect(self.ui.search:GetPropertyChangedSignal("Text"), function()
        self.search = string.lower(self.ui.search.Text); self.dirty = true
    end)
    self.ui.eggScroll = self:scroll(page, UDim2.new(1, 0, 1, -244), UDim2.fromOffset(0, 220))
    self.ui.empty = self:label(self.ui.eggScroll, "", UDim2.new(1, 0, 0, 80), nil, 13, "muted")
    self.ui.empty.TextWrapped = true; self.ui.empty.TextTruncate = Enum.TextTruncate.None
    self.ui.rows = {}
    self.ui.listNote = self:label(page, "", UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 1, -18), 10, "muted")
end

function App:clearESP()
    for _, row in pairs(self.espRows) do
        row.board:Destroy()
        if row.highlight then row.highlight:Destroy() end
    end
    self.espRows = {}
    self.espCount = 0
end
function App:updateESP()
    if not self.espEnabled then
        if next(self.espRows) then self:clearESP() end
        return
    end
    if not self.espGuiFolder or not self.espGuiFolder.Parent then
        self.espGuiFolder = self:node("Folder", PlayerGui, {Name = "VIPKING_V2_ESP_Labels"})
    end
    if not self.espWorldFolder or not self.espWorldFolder.Parent then
        self.espWorldFolder = self:node("Folder", Workspace, {Name = "VIPKING_V2_ESP_Highlights"})
    end
    local list = self:listEggs()
    table.sort(list, function(a, b) return Rules.less(a, b, "Nearest") end)
    local visible, count = {}, 0
    local colors = self:colors()
    for _, entry in ipairs(list) do
        if count >= Config.MaxESP then break end
        if not self.espSelectedOnly or self.selected[entry.name] then
            local egg = entry.object
            local part = egg:IsA("BasePart") and egg or (egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart", true))
            if part then
                count = count + 1
                visible[egg] = true
                local row = self.espRows[egg]
                if not row then
                    local board = self:node("BillboardGui", self.espGuiFolder, {Name = "EggESP", Adornee = part,
                        Size = UDim2.fromOffset(170, 42), StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
                        AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000, ResetOnSpawn = false})
                    local label = self:label(board, "", UDim2.fromScale(1, 1), nil, 12, "text")
                    label.TextXAlignment = Enum.TextXAlignment.Center
                    label.TextWrapped = true; label.TextTruncate = Enum.TextTruncate.None
                    label.TextStrokeTransparency = 0.25
                    label.TextStrokeColor3 = Color3.new(0, 0, 0)
                    row = {board = board, label = label}
                    self.espRows[egg] = row
                end
                row.board.Adornee = part
                local distance = entry.distance == math.huge and "--" or tostring(math.floor(entry.distance))
                row.label.Text = entry.name .. "\n" .. distance .. " studs"
                row.label.TextColor3 = self.selected[entry.name] and colors.accent or colors.text
                if count <= Config.MaxHighlights then
                    if not row.highlight then
                        row.highlight = self:node("Highlight", self.espWorldFolder, {Name = "EggOutline", Adornee = egg,
                            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, FillTransparency = 0.8, OutlineTransparency = 0})
                    end
                    row.highlight.FillColor = colors.accent; row.highlight.OutlineColor = colors.accent
                elseif row.highlight then row.highlight:Destroy(); row.highlight = nil end
            end
        end
    end
    for egg, row in pairs(self.espRows) do
        if not visible[egg] then
            row.board:Destroy()
            if row.highlight then row.highlight:Destroy() end
            self.espRows[egg] = nil
        end
    end
    self.espCount = count
end
function App:buildWorld(page)
    local scroll = self:scroll(page, UDim2.fromScale(1, 1))
    local function button(key, order, callback, primary)
        local obj = self:button(scroll, "", UDim2.new(1, 0, 0, 42), nil, callback, primary)
        obj.LayoutOrder = order
        self:keyText(obj, key)
        return obj
    end
    self.ui.espToggle = button("Egg ESP", 1, function()
        self.espEnabled = not self.espEnabled
        self:updateESP()
        self:log(self.espEnabled and "Egg ESP enabled" or "Egg ESP disabled")
    end, true)
    self.ui.espSelected = button("ESP selected types only", 2, function()
        self.espSelectedOnly = not self.espSelectedOnly; self:updateESP()
    end)
    self.ui.espInfo = self:label(scroll, "", UDim2.new(1, 0, 0, 48), nil, 12, "muted")
    self.ui.espInfo.LayoutOrder = 3; self.ui.espInfo.TextWrapped = true
    self.ui.espInfo.TextTruncate = Enum.TextTruncate.None
    self.ui.volcanoTP = button("TP to volcano", 4, function()
        self:stop("Volcano teleport queued; auto farm stopped")
        self:queueJob({kind = "volcano"})
    end, true)
    self.ui.volcanoSave = button("Save volcano point", 5, function() self:saveVolcano() end)
    self.ui.volcanoAuto = button("Use auto-detection", 6, function()
        self.volcanoSaved = nil
        Config.VolcanoCFrame = nil
        self.volcanoInfo = "Auto-detection selected. Press TP to volcano to scan the loaded map."
        self:log(self.volcanoInfo)
    end)
    self.ui.volcanoInfo = self:label(scroll, "", UDim2.new(1, 0, 0, 74), nil, 12, "muted")
    self.ui.volcanoInfo.LayoutOrder = 7; self.ui.volcanoInfo.TextWrapped = true
    self.ui.volcanoInfo.TextTruncate = Enum.TextTruncate.None
    local note = self:label(scroll, "Auto-detect uses named volcano markers or ground near its edge. If unavailable, visit the volcano once and save your position. Saved points last for this session.",
        UDim2.new(1, 0, 0, 80), nil, 11, "muted")
    note.LayoutOrder = 8; note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
end
function App:renderWorld()
    self.ui.espToggle.Text = self:tr("Egg ESP") .. "  :  " .. self:tr(self.espEnabled and "ON" or "OFF")
    self.ui.espSelected.Text = self:tr("ESP selected types only") .. "  :  " .. self:tr(self.espSelectedOnly and "ON" or "OFF")
    self.ui.espInfo.Text = string.format("ESP labels: %d / %d max. Nearest %d get outlines. Loaded map eggs only.", self.espCount, Config.MaxESP, Config.MaxHighlights)
    self.ui.volcanoInfo.Text = self.volcanoInfo
end

function App:buildSettings(page)
    local scroll = self:scroll(page, UDim2.fromScale(1, 1))
    self.ui.settingButtons = {}
    local order = 0
    local function setting(title, callback, value)
        order = order + 1
        local button = self:button(scroll, title, UDim2.new(1, 0, 0, 42), nil, callback)
        button.LayoutOrder = order
        table.insert(self.ui.settingButtons, {button = button, title = title, value = value})
    end
    local function cycle(field, values)
        local index = table.find(values, self[field]) or 1
        self[field] = values[index % #values + 1]
    end
    setting("Auto types", function() cycle("mode", {"All", "Selected"}) end, function() return self:tr(self.mode) end)
    setting("Speed", function() cycle("speed", {"Balanced", "Fast", "Reliable"}) end, function() return self.speed end)
    for _, entry in ipairs({{"Return after pickup", "autoReturn"}, {"Stow egg tools at home", "stowEggTools"}, {"Anti-AFK", "antiAFK"}}) do
        local title, field = entry[1], entry[2]
        setting(title, function() self[field] = not self[field] end, function() return self:tr(self[field] and "ON" or "OFF") end)
    end
    setting("Auto leave for owner/admin", function()
        self.autoLeave = not self.autoLeave
        if self.autoLeave then for _, player in ipairs(Players:GetPlayers()) do self:checkAdmin(player) end end
    end, function() return self:tr(self.autoLeave and "ON" or "OFF") end)
    setting("Theme", function()
        cycle("theme", {"Galaxy", "Ocean", "Emerald", "Nebula", "Crimson", "Purple"}); self:refreshStyle()
    end, function() return self.theme end)
    setting("Language", function()
        self.language = self.language == "en" and "km" or "en"; self:refreshStyle()
    end, function() return self.language == "en" and "English" or "ខ្មែរ" end)
    setting("UI scale", function() cycle("uiScale", {0.8, 1, 1.15, 1.3}); self:fit() end, function() return tostring(self.uiScale) .. "x (auto-fit)" end)
    setting("Refresh map", function() self:scan(); self:log("Map index refreshed") end)
    setting("Clear retry cooldowns", function() self.cooldown = setmetatable({}, {__mode = "k"}); self:log("Retry cooldowns cleared") end)
    setting("Clear selected types", function() self.selected = {}; self:log("Selected types cleared") end)
    setting("Reset session stats", function() self.picked = 0; self.unverified = 0; self.failures = 0; self.started = os.clock() end)
    setting("Unload VIPKING", function() self:unload() end)
    local note = self:label(scroll, "RightControl: show/hide  |  F6: stop\nSEL marks egg types for Selected mode.\nFast uses an optional prompt helper; Reliable uses the normal prompt hold. Settings last for this session.",
        UDim2.new(1, 0, 0, 90), nil, 11, "muted")
    note.LayoutOrder = order + 1; note.TextWrapped = true; note.TextTruncate = Enum.TextTruncate.None
end

function App:buildUI()
    self.gui = self:node("ScreenGui", PlayerGui, {Name = "VIPKING_V2", ResetOnSpawn = false,
        IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50})
    local shutdown = self:node("BindableFunction", self.gui, {Name = "Shutdown"})
    shutdown.OnInvoke = function() self:unload() end
    self.ui.screen = self:node("Frame", self.gui, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1})
    self.ui.main = self:node("Frame", self.ui.screen, {Name = "Window", Size = UDim2.fromOffset(448, 650),
        Position = UDim2.fromOffset(24, 24), BorderSizePixel = 0, ClipsDescendants = true})
    self:paint(self.ui.main, "BackgroundColor3", "bg"); self:round(self.ui.main, 16)
    local stroke = self:node("UIStroke", self.ui.main, {Thickness = 1})
    self:paint(stroke, "Color", "border")
    self.ui.scale = self:node("UIScale", self.ui.main, {Scale = 1})
    local header = self:node("Frame", self.ui.main, {Size = UDim2.new(1, 0, 0, 72), BackgroundTransparency = 1, Active = true})
    self:label(header, "VIPKING", UDim2.fromOffset(196, 26), UDim2.fromOffset(18, 12), 22).Font = Enum.Font.GothamBold
    self:label(header, "RIDE A PET  /  2.1", UDim2.fromOffset(200, 16), UDim2.fromOffset(19, 40), 10, "muted")
    local stop = self:button(header, "STOP", UDim2.fromOffset(54, 32), UDim2.new(1, -140, 0, 18), function() self:stop("Emergency stop") end)
    self:paint(stop, "TextColor3", "danger")
    self.ui.minimize = self:button(header, "-", UDim2.fromOffset(30, 32), UDim2.new(1, -78, 0, 18), function()
        self.minimized = not self.minimized
        self.ui.content.Visible = not self.minimized
        self.ui.main.Size = UDim2.fromOffset(448, self.minimized and 72 or 650)
        self.ui.minimize.Text = self.minimized and "+" or "-"
        self:fit()
    end)
    self:button(header, "X", UDim2.fromOffset(30, 32), UDim2.new(1, -40, 0, 18), function() self:unload() end)
    self.ui.launcher = self:button(self.ui.screen, "VIP", UDim2.fromOffset(50, 44), UDim2.new(0, 12, 0.5, -22), function() self:toggleVisible() end, true)
    self.ui.launcher.Visible = false
    self.ui.content = self:node("Frame", self.ui.main, {Size = UDim2.new(1, 0, 1, -72), Position = UDim2.fromOffset(0, 72), BackgroundTransparency = 1})
    self.ui.tabs, self.ui.pages = {}, {}
    for i, name in ipairs({"Collect", "World", "Settings", "Activity"}) do
        local button = self:button(self.ui.content, "", UDim2.new(0.25, -13, 0, 34), UDim2.new((i - 1) * 0.25, 14, 0, 4), function() self:showTab(name) end)
        self:keyText(button, name); self.ui.tabs[name] = button
        self.ui.pages[name] = self:node("Frame", self.ui.content, {Size = UDim2.new(1, -32, 1, -104), Position = UDim2.fromOffset(16, 52),
            BackgroundTransparency = 1, Visible = name == self.tab})
    end
    self:buildCollect(self.ui.pages.Collect)
    self:buildWorld(self.ui.pages.World)
    self:buildSettings(self.ui.pages.Settings)
    local activity = self.ui.pages.Activity
    self.ui.diagnostics = self:label(activity, "", UDim2.new(1, 0, 0, 42), nil, 11, "muted")
    self.ui.diagnostics.TextWrapped = true; self.ui.diagnostics.TextTruncate = Enum.TextTruncate.None
    local clear = self:button(activity, "", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 50), function() self.logs = {} end)
    self:keyText(clear, "Clear activity")
    local logScroll = self:scroll(activity, UDim2.new(1, 0, 1, -96), UDim2.fromOffset(0, 96))
    self.ui.logText = self:label(logScroll, "", UDim2.new(1, -4, 0, 0), nil, 12, "muted")
    self.ui.logText.AutomaticSize = Enum.AutomaticSize.Y
    self.ui.logText.TextWrapped = true; self.ui.logText.TextTruncate = Enum.TextTruncate.None
    self.ui.logText.TextYAlignment = Enum.TextYAlignment.Top
    self.ui.status = self:label(self.ui.content, "Ready", UDim2.new(1, -32, 0, 35), UDim2.new(0, 16, 1, -43), 11, "muted")
    self.ui.status.TextWrapped = true; self.ui.status.TextTruncate = Enum.TextTruncate.None
    self:connect(self.ui.screen:GetPropertyChangedSignal("AbsoluteSize"), function() self:fit() end)
    self:connect(self.gui.Destroying, function() self:unload() end)
    local drag
    self:connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            drag = {input = input, start = input.Position, position = self.ui.main.Position}
        end
    end)
    self:connect(UserInputService.InputChanged, function(input)
        if not drag then return end
        local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
        if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == drag.input then
            local delta = input.Position - drag.start
            self.ui.main.Position = UDim2.fromOffset(drag.position.X.Offset + delta.X, drag.position.Y.Offset + delta.Y)
            self:fit()
        end
    end)
    self:connect(UserInputService.InputEnded, function(input)
        if drag and input == drag.input then drag = nil end
    end)
    self:connect(UserInputService.WindowFocusReleased, function() drag = nil end)
    self:connect(UserInputService.InputBegan, function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.RightControl then self:toggleVisible()
        elseif input.KeyCode == Enum.KeyCode.F6 then self:stop("Emergency stop") end
    end)
    self:showTab(self.tab)
    self:fit()
end

function App:renderEggs(list)
    local shown, visible = 0, {}
    for _, entry in ipairs(list) do
        if string.find(string.lower(entry.name), self.search, 1, true) and shown < Config.MaxRows then
            shown = shown + 1
            local egg = entry.object
            visible[egg] = true
            local row = self.ui.rows[egg]
            if not row then
                local frame = self:node("Frame", self.ui.eggScroll, {Size = UDim2.new(1, 0, 0, 66), BorderSizePixel = 0})
                self:paint(frame, "BackgroundColor3", "card"); self:round(frame)
                row = {frame = frame}
                row.rank = self:label(frame, "", UDim2.fromOffset(32, 40), UDim2.fromOffset(10, 12), 13, "accent")
                row.name = self:label(frame, "", UDim2.new(1, -169, 0, 24), UDim2.fromOffset(45, 9), 13)
                row.info = self:label(frame, "", UDim2.new(1, -169, 0, 19), UDim2.fromOffset(45, 35), 10, "muted")
                row.pick = self:button(frame, "", UDim2.fromOffset(56, 36), UDim2.new(1, -114, 0, 15), function()
                    self:queueJob({kind = "pickup", egg = egg})
                end)
                row.select = self:button(frame, "SEL", UDim2.fromOffset(44, 36), UDim2.new(1, -50, 0, 15), function()
                    self.selected[egg.Name] = not self.selected[egg.Name]
                end)
                row.select.TextSize = 10
                self.ui.rows[egg] = row
            end
            row.frame.LayoutOrder = shown
            row.rank.Text = tostring(shown)
            row.name.Text = entry.name
            local retry = self.cooldown[egg]
            local state = self.active and self.active.egg == egg and "BUSY" or self.queued[egg] and "QUEUED" or "READY"
            if state == "READY" and retry and retry.at > os.clock() then state = "RETRY " .. math.ceil(retry.at - os.clock()) .. "s" end
            local distance = entry.distance == math.huge and "--" or tostring(math.floor(entry.distance))
            row.info.Text = distance .. " studs  /  " .. state
            row.pick.Text = self:tr("PICK")
            self:paint(row.select, "BackgroundColor3", self.selected[entry.name] and "accent" or "button")
            self:paint(row.select, "TextColor3", self.selected[entry.name] and "ink" or "muted")
        end
    end
    for egg, row in pairs(self.ui.rows) do
        if not visible[egg] then row.frame:Destroy(); self.ui.rows[egg] = nil end
    end
    self.ui.empty.Visible = shown == 0
    self.ui.empty.Text = self:tr(self.search == "" and "No eligible eggs in the loaded map" or "No eggs match your search")
    local selected = 0
    for _, value in pairs(self.selected) do if value then selected = selected + 1 end end
    self.ui.listNote.Text = string.format("Showing %d / %d  |  Selected types: %d  |  Auto: %s", shown, #list, selected, self.mode)
end
function App:render()
    if not self.alive then return end
    self.ui.status.Text = self.status
    if not self.ui.main.Visible or self.minimized then return end
    self.ui.farm.Text = self:tr(self.auto and "STOP AUTO" or "START AUTO")
    self:paint(self.ui.farm, "BackgroundColor3", self.auto and "danger" or "accent")
    self.ui.sort.Text = self:tr(self.sort)
    if self.tab == "Collect" then
        local list = self:listEggs()
        self.ui.stats.Available.Text = tostring(#list)
        self.ui.stats.Confirmed.Text = tostring(self.picked)
        self.ui.stats.Queue.Text = tostring(#self.queue + (self.active and 1 or 0))
        local elapsed = math.floor(os.clock() - self.started)
        self.ui.stats.Session.Text = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)
        self:renderEggs(list)
    elseif self.tab == "World" then self:renderWorld()
    elseif self.tab == "Settings" then
        for _, entry in ipairs(self.ui.settingButtons) do
            entry.button.Text = self:tr(entry.title) .. (entry.value and ("  :  " .. entry.value()) or "")
        end
    elseif self.tab == "Activity" then
        self.ui.diagnostics.Text = string.format("Prompt helper: %s  |  Scan: %ds\nUnverified: %d  |  Failed jobs: %d",
            Compat.firePrompt and "available" or "normal hold only", Config.ScanInterval, self.unverified, self.failures)
        self.ui.logText.Text = table.concat(self.logs, "\n\n")
    end
end

function App:checkAdmin(player)
    if not self.autoLeave or player == LocalPlayer then return end
    task.spawn(function()
        local admin = table.find(Config.ExtraAdminUserIds, player.UserId) ~= nil
            or (game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId)
        if not admin and game.CreatorType == Enum.CreatorType.Group then
            local ok, rank = pcall(function() return player:GetRankInGroupAsync(game.CreatorId) end)
            admin = ok and rank >= Config.AdminMinGroupRank
        end
        if self.alive and self.autoLeave and admin and player.Parent == Players then
            self:stop("Auto leave: @" .. player.Name)
            LocalPlayer:Kick("VIPKING: owner/admin detected (@" .. player.Name .. ")")
        end
    end)
end

App:buildUI()
App:connect(Workspace.DescendantAdded, function(obj) App:track(obj) end)
App:connect(Workspace.DescendantRemoving, function(obj)
    if App.candidates[obj] then
        -- Defer: Roblox fires DescendantRemoving before Parent changes.
        task.defer(function()
            if App.alive and not obj:IsDescendantOf(Workspace) then App.candidates[obj] = nil; App.dirty = true end
        end)
    end
end)
App:connect(LocalPlayer.CharacterAdded, function()
    App:cancel("Respawn detected; waiting for your character")
    App.home, App.homeCharacter = nil, nil
end)
App:connect(LocalPlayer.CharacterRemoving, function() App:cancel("Character removed; actions cancelled") end)
App:connect(Players.PlayerAdded, function(player) App.dirty = true; App:checkAdmin(player) end)
App:connect(Players.PlayerRemoving, function(player)
    App.dirty = true
end)
App:connect(LocalPlayer.Idled, function()
    if not App.antiAFK then return end
    local ok = pcall(function()
        assert(Compat.virtualUser, "VirtualUser unavailable")
        Compat.virtualUser:CaptureController()
        Compat.virtualUser:ClickButton2(Vector2.zero)
    end)
    if not ok then App.antiAFK = false; App:log("Anti-AFK is unavailable in this client") end
end)
App:scan()
App:log("Ready. Save your return point, then select PICK or START AUTO.")
App:render()

-- One movement worker owns pickup, return, and volcano teleport actions.
task.spawn(function()
    while App.alive do
        local ok, err = pcall(function()
            local char, root, humanoid = App:character()
            if root then
                if not App.home then App.home, App.homeCharacter = root.CFrame, char end
                if root.Anchored or humanoid.Sit then
                    if App.auto or #App.queue > 0 then App.status = "Paused: stand up and wait until your character can move" end
                else
                    local job = App:nextJob()
                    if job then App:runJob(job) end
                end
            elseif App.auto then App.status = "Waiting for character" end
        end)
        if not ok and App.alive then App:releaseInput(); App.active = nil; App:stop("Worker stopped: " .. tostring(err)) end
        task.wait(Config.Tick)
    end
end)

-- Bounded UI work: at most 5 updates/sec; whole-map recovery only every 15 sec.
task.spawn(function()
    local lastScan, lastRender, lastESP = os.clock(), 0, 0
    while App.alive do
        local now = os.clock()
        local ok, err = pcall(function()
            if now - lastScan >= Config.ScanInterval then App:scan(); lastScan = now end
            if App.dirty or now - lastRender >= 0.5 then
                App.dirty = false; lastRender = now; App:render()
            end
        end)
        if not ok and App.alive then
            warn("VIPKING UI: " .. tostring(err))
            App:unload() -- do not keep a hidden collection worker running after UI failure
        end
        if App.alive and now - lastESP >= 0.5 then
            lastESP = now
            local espOK, espError = pcall(function() App:updateESP() end)
            if not espOK then
                App.espEnabled = false
                App:clearESP()
                App:log("ESP disabled after error: " .. tostring(espError))
            end
        end
        task.wait(0.2)
    end
end)
