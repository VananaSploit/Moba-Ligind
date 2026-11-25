local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local repo = "https://raw.githubusercontent.com/viseamn/Visual/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "Ant Evolution",
    Size = Vector2.new(640, 520),
    Layout = "Bottom bar",
    MenuKey = Enum.KeyCode.RightShift,
})

local Main = Window:AddTab("Main", "bug")
local Rewards = Window:AddTab("Rewards", "gift")
local Settings = Window:CreateSettingsTab()

local OrbGroup = Main:AddLeftGroupbox("Orbs", "circle-dot")
local AutoGroup = Main:AddRightGroupbox("Automation", "zap")
local ClaimGroup = Rewards:AddLeftGroupbox("Claims", "gift")
local BPGroup = Rewards:AddRightGroupbox("Battle Pass", "star")
local MiscGroup = Settings:AddLeftGroupbox("Misc", "wrench")

local localPlayer = Players.LocalPlayer
local clientOrbs = workspace:WaitForChild("ClientOrbs")
local antRemotes = ReplicatedStorage:WaitForChild("AntRemotes")

local AntFolder = ReplicatedStorage:WaitForChild("Ant")
local Config = require(AntFolder:WaitForChild("Config"))
local State = require(AntFolder:WaitForChild("Client"):WaitForChild("State"))

local Content
pcall(function()
    Content = require(AntFolder:WaitForChild("Content"))
end)

local orbSpeed = 100
local orbMode = "Big Orb"
local collideMap = {}
local collideConn
local orbitConn
local findOrb

local function now()
    return workspace:GetServerTimeNow()
end

local function claimedPlay()
    local set = {}
    for _, v in State.Json("PlaytimeClaimed") do
        local n = tonumber(v)
        if n then set[n] = true end
    end
    return set
end

local function playedSeconds()
    local start = tonumber(State.Get("PlayStart")) or 0
    if start <= 0 then return 0 end
    return math.max(0, now() - start)
end

local function firstReadyGift()
    local claimed = claimedPlay()
    local secs = playedSeconds()
    for i, gift in ipairs(Config.Playtime or {}) do
        if not claimed[i] and (gift.minutes or 1) * 60 <= secs then
            return i
        end
    end
    return nil
end

local function firstReadyQuest()
    local data = State.Json("Quests")
    if type(data.q) ~= "table" or #data.q == 0 then return nil end
    local allClaimed = true
    for i, q in ipairs(data.q) do
        if q[5] ~= 1 then
            allClaimed = false
            if (tonumber(q[4]) or 0) >= (tonumber(q[3]) or 1) then
                return i
            end
        end
    end
    if allClaimed and data.b ~= 1 then
        return "bonus"
    end
    return nil
end

local function firstReadyRecord()
    local rec = State.Json("Records")
    if type(rec) ~= "table" then rec = {} end
    for i, def in ipairs(Config.Records and Config.Records.List or {}) do
        local row = rec[i]
        if type(row) == "table" then
            local nextGoal = def.goals[(tonumber(row[1]) or 0) + 1]
            if nextGoal and nextGoal <= (tonumber(row[2]) or 0) then
                return def.key
            end
        end
    end
    return nil
end

local function killState()
    local track = State.Json("KillTrack")
    local set = {}
    local list = (type(track) == "table" and type(track.c) == "table") and track.c or {}
    for _, v in ipairs(list) do
        set[tonumber(v) or -1] = true
    end
    return set
end

local function firstReadyKill()
    if not (Content and Content.Kills and Content.Kills.Milestones) then return nil end
    local claimed = killState()
    local kills = tonumber(State.Get("Kills")) or 0
    for i, m in ipairs(Content.Kills.Milestones) do
        if not claimed[i] and m.n <= kills then
            return i
        end
    end
    return nil
end

local function dailyReady()
    local nextAt = tonumber(State.Get("DailyNext")) or 0
    return nextAt <= now()
end

local function setCollide(enabled)
    if enabled then
        if collideConn then return end
        collideConn = RunService.Stepped:Connect(function()
            local character = localPlayer.Character
            if not character then return end
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    if collideMap[part] == nil then
                        collideMap[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end)
    else
        if collideConn then
            collideConn:Disconnect()
            collideConn = nil
        end
        for part, canCollide in pairs(collideMap) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        table.clear(collideMap)
    end
end

local function startOrbit()
    if orbitConn then return end
    orbitConn = RunService.Heartbeat:Connect(function(delta)
        if not _G.Orb then return end
        local character = localPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not rootPart then return end
        local orb = findOrb(rootPart)
        if not (orb and orb.Parent) then return end
        local target = orb.CFrame
        local dist = (target.Position - rootPart.Position).Magnitude
        rootPart.AssemblyLinearVelocity = Vector3.zero
        if dist < 0.5 then return end
        rootPart.CFrame = rootPart.CFrame:Lerp(target, math.min(orbSpeed * delta / dist, 1))
    end)
end

function findOrb(rootPart)
    local bestTier = -math.huge
    local bestDist = math.huge
    local best
    for _, orb in ipairs(clientOrbs:GetChildren()) do
        if orb:IsA("MeshPart") then
            local dist = (orb.Position - rootPart.Position).Magnitude
            if orbMode == "Nearest" then
                if dist < bestDist then
                    bestDist = dist
                    best = orb
                end
            else
                local tier = tonumber(orb:GetAttribute("Tier"))
                if tier then
                    if tier > bestTier or (tier == bestTier and dist < bestDist) then
                        bestTier = tier
                        bestDist = dist
                        best = orb
                    end
                end
            end
        end
    end
    return best
end

local function stopOrbit()
    if orbitConn then
        orbitConn:Disconnect()
        orbitConn = nil
    end
    setCollide(false)
end

local function Evolve()
    task.spawn(function()
        while _G.Evolve do
            local power = tonumber(State.Get("Power")) or 0
            local stage = tonumber(State.Get("Stage")) or 1
            local need = tonumber(State.Get("Need")) or Config.Need(stage)
            local rebirths = tonumber(State.Get("Rebirths")) or 0
            local top = Config.TopStage(rebirths)
            if stage < top and power >= need then
                pcall(function()
                    antRemotes.Evolve:InvokeServer()
                end)
                task.wait(0.5)
            else
                task.wait(0.25)
            end
        end
    end)
end

local function Rebirth()
    task.spawn(function()
        while _G.Rebirth do
            local power = tonumber(State.Get("Power")) or 0
            local stage = tonumber(State.Get("Stage")) or 1
            local need = tonumber(State.Get("Need")) or Config.Need(stage)
            local rebirths = tonumber(State.Get("Rebirths")) or 0
            local top = Config.TopStage(rebirths)
            if stage >= top and power >= need then
                pcall(function()
                    antRemotes.Rebirth:InvokeServer()
                end)
                task.wait(1)
            else
                task.wait(0.5)
            end
        end
    end)
end

local function Attack()
    task.spawn(function()
        while _G.Attack do
            task.wait()
            pcall(function()
                local lp = Players.LocalPlayer
                local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if not root then return end
                local bestDist = math.huge
                local target
                for _, part in ipairs(workspace.Ants:GetDescendants()) do
                    if part.Name == "HumanoidRootPart" and part:IsA("BasePart") then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            target = part
                        end
                    end
                end
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= lp then
                        local character = plr.Character
                        local other = character and character:FindFirstChild("HumanoidRootPart")
                        if other then
                            local dist = (other.Position - root.Position).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                target = other
                            end
                        end
                    end
                end
                if target then
                    local entityId = target:GetAttribute("EntityId")
                    antRemotes.Bite:FireServer(entityId)
                end
                task.wait(0.2)
            end)
        end
    end)
end

local function AutoDaily()
    task.spawn(function()
        while _G.AutoDaily do
            if dailyReady() then
                pcall(function()
                    antRemotes.ClaimDaily:InvokeServer()
                end)
                task.wait(1.5)
            else
                task.wait(2)
            end
        end
    end)
end

local function AutoPlaytime()
    task.spawn(function()
        while _G.AutoPlaytime do
            local idx = firstReadyGift()
            if idx then
                pcall(function()
                    antRemotes.ClaimPlaytime:InvokeServer(idx)
                end)
                task.wait(0.8)
            else
                task.wait(2)
            end
        end
    end)
end

local function AutoQuests()
    task.spawn(function()
        while _G.AutoQuests do
            local ready = firstReadyQuest()
            if ready then
                pcall(function()
                    antRemotes.ClaimQuest:InvokeServer(ready)
                end)
                task.wait(0.8)
            else
                task.wait(2)
            end
        end
    end)
end

local function AutoRecords()
    task.spawn(function()
        while _G.AutoRecords do
            local key = firstReadyRecord()
            if key then
                pcall(function()
                    antRemotes.ClaimRecord:InvokeServer(key)
                end)
                task.wait(0.8)
            else
                task.wait(2)
            end
        end
    end)
end

local function AutoKills()
    task.spawn(function()
        while _G.AutoKills do
            local idx = firstReadyKill()
            if idx then
                pcall(function()
                    antRemotes.ClaimKill:InvokeServer(idx)
                end)
                task.wait(0.8)
            else
                task.wait(2)
            end
        end
    end)
end

local function AutoGroupClaim()
    task.spawn(function()
        while _G.AutoGroupClaim do
            if State.Get("CommunityClaimed") ~= true then
                pcall(function()
                    antRemotes.CommunityClaim:InvokeServer()
                end)
                task.wait(3)
            else
                task.wait(5)
            end
        end
    end)
end

local function AutoBP()
    task.spawn(function()
        while _G.AutoBP do
            pcall(function()
                antRemotes.PassAction:InvokeServer("claimAll")
            end)
            task.wait(2.5)
        end
    end)
end

local function AutoBPQuests()
    task.spawn(function()
        while _G.AutoBPQuests do
            local bp = State.Json("BP")
            local w = type(bp.w) == "table" and bp.w or {}
            local qlist = type(w.q) == "table" and w.q or {}
            for i, q in ipairs(qlist) do
                if type(q) == "table" and q[4] ~= 1 then
                    local goal = tonumber(q[2]) or 1
                    local progress = tonumber(q[3]) or 0
                    if progress >= goal then
                        pcall(function()
                            antRemotes.PassAction:InvokeServer("weekly", i)
                        end)
                        task.wait(0.6)
                    end
                end
            end
            if w.b ~= 1 then
                local allDone = #qlist > 0
                for _, q in ipairs(qlist) do
                    if type(q) ~= "table" or q[4] ~= 1 then
                        allDone = false
                        break
                    end
                end
                if allDone then
                    pcall(function()
                        antRemotes.PassAction:InvokeServer("weeklyBonus")
                    end)
                    task.wait(0.6)
                end
            end
            task.wait(2)
        end
    end)
end

OrbGroup:AddToggle("CollectOrb", {
    Text = "Collect Orb",
    Default = false,
    Callback = function(enabled)
        _G.Orb = enabled
        if enabled then
            setCollide(true)
            startOrbit()
        else
            stopOrbit()
        end
    end,
})

OrbGroup:AddDropdown("OrbMode", {
    Text = "Select Orb",
    Values = { "Big Orb", "Nearest" },
    Default = "Big Orb",
    Callback = function(value)
        orbMode = value
    end,
})

OrbGroup:AddSlider("OrbSpeed", {
    Text = "Set Speed",
    Min = 30,
    Max = 100,
    Default = 80,
    Callback = function(value)
        orbSpeed = value
    end,
})

AutoGroup:AddToggle("AutoEvolve", {
    Text = "Auto Evolve",
    Default = false,
    Callback = function(enabled)
        _G.Evolve = enabled
        if enabled then Evolve() end
    end,
})

AutoGroup:AddToggle("AutoRebirth", {
    Text = "Auto Rebirth",
    Default = false,
    Callback = function(enabled)
        _G.Rebirth = enabled
        if enabled then Rebirth() end
    end,
})

AutoGroup:AddToggle("AttackAura", {
    Text = "Attack Aura",
    Default = false,
    Callback = function(enabled)
        _G.Attack = enabled
        if enabled then Attack() end
    end,
})

ClaimGroup:AddToggle("AutoDaily", {
    Text = "Auto Daily",
    Default = false,
    Callback = function(enabled)
        _G.AutoDaily = enabled
        if enabled then AutoDaily() end
    end,
})

ClaimGroup:AddToggle("AutoPlaytime", {
    Text = "Auto Playtime",
    Default = false,
    Callback = function(enabled)
        _G.AutoPlaytime = enabled
        if enabled then AutoPlaytime() end
    end,
})

ClaimGroup:AddToggle("AutoQuests", {
    Text = "Auto Quests",
    Default = false,
    Callback = function(enabled)
        _G.AutoQuests = enabled
        if enabled then AutoQuests() end
    end,
})

ClaimGroup:AddToggle("AutoRecords", {
    Text = "Auto Records",
    Default = false,
    Callback = function(enabled)
        _G.AutoRecords = enabled
        if enabled then AutoRecords() end
    end,
})

ClaimGroup:AddToggle("AutoKills", {
    Text = "Auto Kill Milestones",
    Default = false,
    Callback = function(enabled)
        _G.AutoKills = enabled
        if enabled then AutoKills() end
    end,
})

ClaimGroup:AddToggle("AutoGroupClaim", {
    Text = "Auto Group Reward",
    Default = false,
    Callback = function(enabled)
        _G.AutoGroupClaim = enabled
        if enabled then AutoGroupClaim() end
    end,
})

BPGroup:AddToggle("AutoBP", {
    Text = "Auto Claim Pass Rewards",
    Default = false,
    Callback = function(enabled)
        _G.AutoBP = enabled
        if enabled then AutoBP() end
    end,
})

BPGroup:AddToggle("AutoBPQuests", {
    Text = "Auto BP Weekly Quests",
    Default = false,
    Callback = function(enabled)
        _G.AutoBPQuests = enabled
        if enabled then AutoBPQuests() end
    end,
})

MiscGroup:AddButton({
    Text = "Unload UI",
    Callback = function()
        Library:Unload()
    end,
})

ThemeManager:SetLibrary(Window)
SaveManager:SetLibrary(Window)
ThemeManager:SetFolder("Byte/AntEvolution")
SaveManager:SetFolder("Byte/AntEvolution")
SaveManager:BuildConfigSection(Settings)
ThemeManager:ApplyToTab(Settings)
ThemeManager:LoadDefault()
SaveManager:LoadAutoloadConfig()
