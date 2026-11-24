local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerCharacter = Remotes:WaitForChild("PlayerCharacter")
local registerImpact = PlayerCharacter.Update:WaitForChild("RegisterImpact")
local CtrlFolder = ReplicatedStorage:WaitForChild("Controllers")
local WeaponModules = ReplicatedStorage:WaitForChild("WeaponModulesShared")
local WeaponInv = Remotes:WaitForChild("WeaponInventory")

local SAVE_ROOT = "Byte"
local SAVE_DIR = "Byte/Dueling_Battle"
local SKIN_FILE = SAVE_DIR .. "/skins.json"
local SEQ_FILE = SAVE_DIR .. "/sequences.json"

local function ensureFolder(path)
    if type(isfolder) == "function" and type(makefolder) == "function" then
        if not isfolder(path) then pcall(makefolder, path) end
    end
end

ensureFolder(SAVE_ROOT)
ensureFolder(SAVE_DIR)

local function readJson(path)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    if not isfile(path) then return nil end
    local ok, data = pcall(readfile, path)
    if not ok or not data or data == "" then return nil end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
    if ok2 and type(decoded) == "table" then return decoded end
    return nil
end

local function writeJson(path, tbl)
    if type(writefile) ~= "function" then return end
    ensureFolder(SAVE_ROOT); ensureFolder(SAVE_DIR)
    local ok, encoded = pcall(function() return HttpService:JSONEncode(tbl) end)
    if ok then pcall(writefile, path, encoded) end
end

local savedSkins = {}
local savedSeq = { intro = nil, death = nil, victory = nil }

do
    local data = readJson(SKIN_FILE)
    if data then
        for k, v in pairs(data) do
            if type(k) == "string" and type(v) == "string" then
                savedSkins[k] = v
            end
        end
    end
end

do
    local data = readJson(SEQ_FILE)
    if data then
        for _, k in ipairs({ "intro", "death", "victory" }) do
            if type(data[k]) == "string" then savedSeq[k] = data[k] end
        end
    end
end

local function saveSkins() writeJson(SKIN_FILE, savedSkins) end
local function saveSequences() writeJson(SEQ_FILE, savedSeq) end

local noCDDodge = false
local dodgeInterval = 0.0
local lastDodgeStart = 0

local function hookBaseActionManager()
    local ok, BAM = pcall(require, ReplicatedStorage.Modules.BaseActionManager)
    if not ok or type(BAM) ~= "table" or BAM.__ByteHooked then return end
    BAM.__ByteHooked = true

    local ActionsFolder = ReplicatedStorage:FindFirstChild("Actions")
    local IntroActions = ActionsFolder and ActionsFolder:FindFirstChild("IntroActions")
    local DeathActions = ActionsFolder and ActionsFolder:FindFirstChild("DeathActions")
    local VictoryActions = ActionsFolder and ActionsFolder:FindFirstChild("VictoryActions")

    local function loadAs(self, key, moduleScript)
        if not moduleScript then return end
        local okReq, mod = pcall(require, moduleScript)
        if not okReq or type(mod) ~= "table" then return end
        self.LoadedActions = self.LoadedActions or {}
        self._loadedThisActionModule = self._loadedThisActionModule or {}
        if not self._loadedThisActionModule[moduleScript] then
            if type(mod.bindEffects) == "function" then
                pcall(mod.bindEffects, self.CharacterHandler)
            end
            self._loadedThisActionModule[moduleScript] = true
        end
        self.LoadedActions[key] = mod
    end

    local function isLocal(self)
        local h = self and self.CharacterHandler
        return h and h.IsLocalPlayer == true
    end

    local origSwitchToAction = BAM.SwitchToAction
    BAM.SwitchToAction = function(self, key, props, dispatch)
        if type(key) == "string" and isLocal(self) then
            if key == "Death" and savedSeq.death and DeathActions then
                local chosen = DeathActions:FindFirstChild(savedSeq.death)
                if chosen then pcall(loadAs, self, "Death", chosen) end
            elseif key == "Victory" and savedSeq.victory and VictoryActions then
                local chosen = VictoryActions:FindFirstChild(savedSeq.victory)
                if chosen then pcall(loadAs, self, "Victory", chosen) end
            end
        end
        return origSwitchToAction(self, key, props, dispatch)
    end

    local origCanStartDodge = BAM.CanStartDodge
    BAM.CanStartDodge = function(self)
        if not noCDDodge then return origCanStartDodge(self) end
        if self.CurrentMiniStun then return false end
        if dodgeInterval > 0 and (os.clock() - lastDodgeStart) < dodgeInterval then
            return false
        end
        return true
    end

    local origActionStartedConnect
    local function patchActionStartedTracking(self)
        if self.__ByteDodgeTracked then return end
        self.__ByteDodgeTracked = true
        if self.ActionStarted and self.ActionStarted.Connect then
            self.ActionStarted:Connect(function(action)
                if action and action.ActionType == "Dodge" then
                    lastDodgeStart = os.clock()
                end
            end)
        end
    end

    local origSwitchToAction2 = BAM.SwitchToAction
    BAM.SwitchToAction = function(self, key, props, dispatch)
        if key == "Dodge" and self and self.CharacterHandler
            and self.CharacterHandler.IsLocalPlayer then
            lastDodgeStart = os.clock()
        end
        return origSwitchToAction2(self, key, props, dispatch)
    end

    local origSwitchToActionModule = BAM.SwitchToActionModule
    BAM.SwitchToActionModule = function(self, mod, props)
        if isLocal(self) and typeof(mod) == "Instance" and mod:IsA("ModuleScript") then
            local swap
            if IntroActions and savedSeq.intro and mod:IsDescendantOf(IntroActions) then
                swap = IntroActions:FindFirstChild(savedSeq.intro)
            elseif DeathActions and savedSeq.death and mod:IsDescendantOf(DeathActions) then
                swap = DeathActions:FindFirstChild(savedSeq.death)
            elseif VictoryActions and savedSeq.victory and mod:IsDescendantOf(VictoryActions) then
                swap = VictoryActions:FindFirstChild(savedSeq.victory)
            end
            if swap and swap ~= mod then mod = swap end
        end
        return origSwitchToActionModule(self, mod, props)
    end
end

local hookOk, hookErr = pcall(hookBaseActionManager)

local connections = {}
local function track(c) connections[#connections + 1] = c; return c end

local state = {
    AP_Enabled = false,
    AP_Chance = 100,
    GM_Enabled = false,
    AutoUlt_Enabled = false,
    AutoUlt_Delay = 0.5,
    UnlockAll = true,
}

local Library, Window

local CharacterController, TargetLockController
pcall(function() CharacterController = require(CtrlFolder.CharacterController) end)
pcall(function() TargetLockController = require(CtrlFolder.TargetLockController) end)

local function getHandler()
    if not CharacterController then return nil end
    local ok, h = pcall(CharacterController.GetLocalCharacterHandler, CharacterController)
    if ok and type(h) == "table" and h.ActionManager then return h end
    return nil
end

local parryBusy = false

local function parryImpact(id)
    local h = getHandler()
    if not h or h.IsParrying == true then return end
    local am, prev = h.ActionManager, h.IsParrying
    h.IsParrying = true
    parryBusy = true
    task.spawn(function()
        local deadline = os.clock() + 0.6
        while true do
            RunService.Heartbeat:Wait()
            local pending = am and am.UnresolvedImpacts and am.UnresolvedImpacts[id] ~= nil
            if not pending or os.clock() > deadline then break end
        end
        local h2 = getHandler()
        if h2 == h and h2.IsParrying == true then h2.IsParrying = prev end
        parryBusy = false
    end)
end

local function dodgeImpact(id)
    local h = getHandler()
    if not h then return end
    local am, prev = h.ActionManager, h.IsDodging
    h.IsDodging = true
    task.spawn(function()
        local deadline = os.clock() + 0.6
        while true do
            RunService.Heartbeat:Wait()
            local pending = am and am.UnresolvedImpacts and am.UnresolvedImpacts[id] ~= nil
            if not pending or os.clock() > deadline then break end
        end
        local h2 = getHandler()
        if h2 == h and h2.IsDodging == true then h2.IsDodging = prev end
    end)
end

track(registerImpact.OnClientEvent:Connect(function(id, meta)
    if not state.AP_Enabled then return end
    if type(id) ~= "number" and type(id) ~= "string" then return end
    if type(meta) == "table" and meta.sourceModule == nil then return end
    if state.AP_Chance < math.random() * 100 then return end
    parryImpact(id)
end))

track(registerImpact.OnClientEvent:Connect(function(id)
    if not state.GM_Enabled then return end
    if type(id) ~= "number" and type(id) ~= "string" then return end
    dodgeImpact(id)
end))

local function actionIsPostureBreak(ca)
    if not ca then return false end
    if ca.IsPostureBreak then return true end
    if ca.StaggerInfo and ca.StaggerInfo.staggerType == "PostureBreak" then return true end
    if ca.ActionType == "Stagger" then
        local props = ca.Properties
        if props and props.staggerType == "PostureBreak" then return true end
    end
    return false
end

local function postureBreakVisible(me)
    if TargetLockController and TargetLockController.CriticalStrikeTarget then
        return true
    end
    if not CharacterController or not me or not me.Root then return false end
    local myPos = me.Root.CFrame.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local h = CharacterController:GetCharacterHandler(nil, p.Character)
                or CharacterController:GetCharacterHandler(p.Character)
            if h and h.ActionManager and h.Root then
                if actionIsPostureBreak(h.ActionManager.CurrentAction) then
                    local dist = (h.Root.CFrame.Position - myPos).Magnitude
                    if dist <= 40 then return true end
                end
            end
        end
    end
    return false
end

local lastAutoUlt = 0
track(RunService.Heartbeat:Connect(function()
    if not state.AutoUlt_Enabled then return end
    local now = os.clock()
    if now - lastAutoUlt < (state.AutoUlt_Delay or 0.5) then return end

    local me = getHandler()
    if not me or not me.OriginalModel then return end
    if (me.OriginalModel:GetAttribute("UltimateEnergy") or 0) < 100 then return end
    if not me.EquippedWeapon then return end

    local am = me.ActionManager
    if am and am.CurrentAction and not am.CurrentAction.CanCancel then return end

    if not postureBreakVisible(me) then return end

    me._desiredQueuedAction = "Ultimate"
    me._desiredQueuedActionDuration = nil
    lastAutoUlt = now
end))

local function findController(name, validator)
    local mod = CtrlFolder:FindFirstChild(name)
    if mod then
        local ok, res = pcall(require, mod)
        if ok and type(res) == "table" and validator(res) then return res end
    end
    if type(getgc) == "function" then
        for _, obj in getgc(true) do
            if type(obj) == "table" then
                local ok, pass = pcall(validator, obj)
                if ok and pass then return obj end
            end
        end
    end
    return nil
end

local WeaponCtrl = findController("WeaponInventoryController", function(t)
    return t.UnlockedWeapons ~= nil and t.StateLoaded ~= nil
end)
local CharCtrl = findController("CharacterController", function(t)
    return type(t.GetLocalCharacterHandler) == "function"
end)
local IntroCtrl = findController("IntroInventoryController", function(t)
    return t.UnlockedIntros ~= nil and t.StateLoaded ~= nil
end)
local MapCtrl = findController("MapInventoryController", function(t)
    return t.UnlockedMaps ~= nil and t.StateLoaded ~= nil
end)
local SeqCtrl = findController("SequenceInventoryController", function(t)
    return type(t.Kinds) == "table" and t.Kinds.Death ~= nil and t.Kinds.Victory ~= nil
end)

local ActionsFolder = ReplicatedStorage:FindFirstChild("Actions")
local IntroActions = ActionsFolder and ActionsFolder:FindFirstChild("IntroActions")
local DeathActions = ActionsFolder and ActionsFolder:FindFirstChild("DeathActions")
local VictoryActions = ActionsFolder and ActionsFolder:FindFirstChild("VictoryActions")
local MapModules = ReplicatedStorage:FindFirstChild("MapModules")

local function unlockSkins()
    if not WeaponCtrl or not state.UnlockAll then return end
    local changed = false
    for _, child in ipairs(WeaponModules:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok, info = pcall(require, child)
            if ok and info and info.WeaponInfo and info.WeaponInfo.Cosmetics then
                local bucket = WeaponCtrl.WeaponToUnlockedCosmetics[child.Name] or {}
                WeaponCtrl.WeaponToUnlockedCosmetics[child.Name] = bucket
                for skin, mod in pairs(info.WeaponInfo.Cosmetics) do
                    if type(skin) == "string" and typeof(mod) == "Instance" and bucket[skin] ~= true then
                        bucket[skin] = true
                        changed = true
                    end
                end
            end
        end
    end
    if changed then
        pcall(function() WeaponCtrl.StateLoaded:Fire(WeaponCtrl.UnlockedWeapons) end)
    end
end

local function unlockFolder(folder, bucket)
    if not folder or not bucket then return false end
    local changed = false
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ModuleScript") and bucket[child.Name] ~= true then
            bucket[child.Name] = true
            changed = true
        end
    end
    return changed
end

local function unlockIntros()
    if not IntroCtrl or not IntroActions or not state.UnlockAll then return end
    if unlockFolder(IntroActions, IntroCtrl.UnlockedIntros) then
        pcall(function() IntroCtrl.StateLoaded:Fire(IntroCtrl.SelectedIntro) end)
    end
end

local function unlockDeaths()
    if not SeqCtrl or not DeathActions or not state.UnlockAll then return end
    local D = SeqCtrl.Kinds and SeqCtrl.Kinds.Death
    if not D or not D.Unlocked then return end
    if unlockFolder(DeathActions, D.Unlocked) then
        pcall(function() D.StateLoaded:Fire(D.Selected) end)
    end
end

local function unlockVictories()
    if not SeqCtrl or not VictoryActions or not state.UnlockAll then return end
    local V = SeqCtrl.Kinds and SeqCtrl.Kinds.Victory
    if not V or not V.Unlocked then return end
    if unlockFolder(VictoryActions, V.Unlocked) then
        pcall(function() V.StateLoaded:Fire(V.Selected) end)
    end
end

local function unlockMaps()
    if not MapCtrl or not MapModules or not state.UnlockAll then return end
    if unlockFolder(MapModules, MapCtrl.UnlockedMaps) then
        pcall(function() MapCtrl.StateLoaded:Fire(MapCtrl.UnlockedMaps) end)
    end
end

local function unlockAll()
    unlockSkins()
    unlockIntros()
    unlockDeaths()
    unlockVictories()
    unlockMaps()
end

local function selectSequence(kind, name)
    if type(kind) ~= "string" or type(name) ~= "string" then return end
    if kind == "Intro" and IntroCtrl then
        IntroCtrl.SelectedIntro = name
        pcall(function() IntroCtrl.IntroSelected:Fire(name) end)
    elseif (kind == "Death" or kind == "Victory") and SeqCtrl then
        local K = SeqCtrl.Kinds and SeqCtrl.Kinds[kind]
        if K then
            K.Selected = name
            pcall(function() K.SequenceSelected:Fire(name) end)
        end
    end
end

local function reapplySelections()
    if savedSeq.intro then selectSequence("Intro", savedSeq.intro) end
    if savedSeq.death then selectSequence("Death", savedSeq.death) end
    if savedSeq.victory then selectSequence("Victory", savedSeq.victory) end
end

local function applySkin(weaponName, cosmeticName)
    if not CharCtrl then return end
    local handler = CharCtrl:GetLocalCharacterHandler()
    if not handler then return end

    local mounted = handler.OriginalModel and handler.OriginalModel:FindFirstChild("MountedWeapons")
    if mounted then
        local w = mounted:FindFirstChild(weaponName)
        if w then w:SetAttribute("CurrentCosmetic", cosmeticName) end
    end

    local weaponTable = handler.WeaponToHandler
    if not weaponTable then return end
    local wHandler = weaponTable[weaponName]
    if not wHandler then return end

    if wHandler.SetCosmetic then
        pcall(function() wHandler:SetCosmetic(cosmeticName) end)
    end
    if wHandler.SetWeaponHolding then
        pcall(function() wHandler:SetWeaponHolding(wHandler.IsHolding == true, true) end)
    elseif wHandler._setWeaponHolding then
        pcall(function() wHandler:_setWeaponHolding(wHandler.IsHolding == true) end)
    end
end

local function applyAllSkins()
    for name, skin in pairs(savedSkins) do
        applySkin(name, skin)
    end
end

local function syncSkinSelections()
    if not WeaponCtrl then return end
    pcall(function()
        for name, skin in pairs(savedSkins) do
            if WeaponCtrl.WeaponToSelectedCosmetic then
                WeaponCtrl.WeaponToSelectedCosmetic[name] = skin
            end
            if WeaponCtrl.WeaponCosmeticChanged then
                task.spawn(function()
                    WeaponCtrl.WeaponCosmeticChanged:Fire(name, skin)
                end)
            end
        end
    end)
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()

    if method == "FireServer" and self.Name == "Request_SetSelectedCosmetic" then
        local args = { ... }
        local weapon, cosmetic = args[1], args[2]
        if type(weapon) == "string" and type(cosmetic) == "string" then
            savedSkins[weapon] = cosmetic
            saveSkins()
            if WeaponCtrl then
                pcall(function()
                    WeaponCtrl.WeaponToSelectedCosmetic[weapon] = cosmetic
                    task.spawn(function()
                        WeaponCtrl.WeaponCosmeticChanged:Fire(weapon, cosmetic)
                    end)
                end)
            end
            applySkin(weapon, cosmetic)
            return
        end
    end

    if method == "FireServer" and self.Name == "Request_SetSequence" then
        local args = { ... }
        local kind, name = args[1], args[2]
        if type(kind) == "string" and type(name) == "string" then
            selectSequence(kind, name)
            local lower = string.lower(kind)
            if lower == "intro" or lower == "death" or lower == "victory" then
                savedSeq[lower] = name
                saveSequences()
            end
            return
        end
    end

    if method == "FireServer" and self.Name == "Request_SetIntroSequence" then
        local args = { ... }
        if type(args[1]) == "string" then
            selectSequence("Intro", args[1])
            savedSeq.intro = args[1]
            saveSequences()
            return
        end
    end

    return oldNamecall(self, ...)
end)

local lastDrift = 0
track(RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastDrift < 0.4 then return end
    lastDrift = now

    if not CharCtrl then return end
    local handler = CharCtrl:GetLocalCharacterHandler()
    if not handler then return end
    local wTable = handler.WeaponToHandler
    if not wTable then return end

    for weapon, cosmetic in pairs(savedSkins) do
        local w = wTable[weapon]
        if w and w.CurrentCosmetic and w.CurrentCosmetic ~= cosmetic then
            applySkin(weapon, cosmetic)
        end
    end
end))

track(WeaponInv.LoadState.OnClientEvent:Connect(function()
    task.defer(function()
        unlockSkins()
        syncSkinSelections()
        applyAllSkins()
    end)
end))

local SeqRemote = Remotes:FindFirstChild("SequenceInventory")
local MapRemote = Remotes:FindFirstChild("MapInventory")

if SeqRemote then
    local loadIntros = SeqRemote:FindFirstChild("LoadState")
    if loadIntros then
        track(loadIntros.OnClientEvent:Connect(function()
            task.defer(function()
                unlockIntros()
                if savedSeq.intro then selectSequence("Intro", savedSeq.intro) end
            end)
        end))
    end
    local loadSeq = SeqRemote:FindFirstChild("Sequence_LoadState")
    if loadSeq then
        track(loadSeq.OnClientEvent:Connect(function(kind)
            task.defer(function()
                if kind == "Death" then
                    unlockDeaths()
                    if savedSeq.death then selectSequence("Death", savedSeq.death) end
                elseif kind == "Victory" then
                    unlockVictories()
                    if savedSeq.victory then selectSequence("Victory", savedSeq.victory) end
                else
                    unlockDeaths(); unlockVictories()
                    reapplySelections()
                end
            end)
        end))
    end
end

if MapRemote then
    local loadMaps = MapRemote:FindFirstChild("LoadState")
    if loadMaps then
        track(loadMaps.OnClientEvent:Connect(function()
            task.defer(unlockMaps)
        end))
    end
end

local function onCharacterReady(h)
    if not h then return end
    task.spawn(function()
        local deadline = os.clock() + 8
        while os.clock() < deadline do
            local wTable = h.WeaponToHandler
            if wTable and next(wTable) ~= nil then
                unlockAll()
                syncSkinSelections()
                applyAllSkins()
                reapplySelections()
                return
            end
            task.wait(0.15)
        end
    end)
end

pcall(function()
    if CharCtrl.LocalCharacterLoaded and CharCtrl.LocalCharacterLoaded.Connect then
        track(CharCtrl.LocalCharacterLoaded:Connect(onCharacterReady))
    end
end)

unlockAll()
syncSkinSelections()
applyAllSkins()
reapplySelections()

pcall(function()
    local h = CharCtrl and CharCtrl:GetLocalCharacterHandler()
    if h then onCharacterReady(h) end
end)

local repo = "https://raw.githubusercontent.com/viseamn/Visual/main/"
Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "SaveManager.lua"))()

Window = Library:CreateWindow({
    Title = "Byte | Dueling Grounds",
    Layout = "Bottom bar",
    MenuKey = Enum.KeyCode.RightShift,
    AutoHide = false,
})

local Combat = Window:AddTab("Combat", "swords")
local Unlocks = Window:AddTab("Unlocks", "unlock")
local Settings = Window:CreateSettingsTab()

local Toggles, Options = Library.Toggles, Library.Options

local gAP = Combat:AddLeftGroupbox("Auto Parry", "shield")
local gGM = Combat:AddLeftGroupbox("God Mode", "sparkles")
local gUlt = Combat:AddRightGroupbox("Auto Ultimate", "zap")
local gMove = Combat:AddRightGroupbox("Movement", "footprints")

local apToggle = gAP:AddToggle("AP_Enabled", {
    Text = "Enable Auto Parry",
    Default = false,
    Tooltip = "Resolves every incoming impact as a parry.",
    Notify = true,
    Callback = function(v) state.AP_Enabled = v end,
})

apToggle:AddKeyPicker("AP_Key", {
    Default = "G",
    Mode = "Toggle",
    SyncToggleState = true,
    Notify = true,
    Text = "Auto Parry",
})

pcall(function()
    local kp = Options and Options.AP_Key
    if kp then
        if type(kp.SetNotify) == "function" then kp:SetNotify(true) end
        if type(kp.AddNotify) == "function" then kp:AddNotify(true) end
        kp.Notify = true
    end
    if apToggle then
        if type(apToggle.SetNotify) == "function" then apToggle:SetNotify(true) end
        if type(apToggle.AddNotify) == "function" then apToggle:AddNotify(true) end
        apToggle.Notify = true
    end
end)

gAP:AddSlider("AP_Chance", {
    Text = "Parry Chance",
    Default = 100,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Callback = function(v) state.AP_Chance = v end,
})

gGM:AddToggle("GM_Enabled", {
    Text = "Enable God Mode",
    Default = false,
    Tooltip = "Every incoming impact resolves as a Dodge on your client.",
    Keybind = "H",
    Callback = function(v) state.GM_Enabled = v end,
})

gUlt:AddToggle("AutoUlt_Enabled", {
    Text = "Enable Auto Ultimate",
    Default = false,
    Tooltip = "Fires your Ultimate when the enemy is posture-broken and your meter is full.",
    Keybind = "K",
    Callback = function(v) state.AutoUlt_Enabled = v end,
})

gUlt:AddSlider("AutoUlt_Delay", {
    Text = "Min Delay",
    Default = 0.5,
    Min = 0.1,
    Max = 5,
    Rounding = 1,
    Suffix = "s",
    Callback = function(v) state.AutoUlt_Delay = v end,
})

gMove:AddToggle("NoCDDodge", {
    Text = "No Cooldown Dodge",
    Default = false,
    Tooltip = "Skips stamina + action-cancel gates on dodges. Spam Q / Shift freely.",
    Keybind = "J",
    Callback = function(v) noCDDodge = v end,
})

gMove:AddSlider("DodgeInterval", {
    Text = "Dodge Interval",
    Default = 0.0,
    Min = 0.0,
    Max = 0.5,
    Rounding = 0.1,
    Suffix = "s",
    Callback = function(v) dodgeInterval = v end,
})

local gUnlocks = Unlocks:AddLeftGroupbox("Unlocks", "unlock")

gUnlocks:AddToggle("UnlockAll", {
    Text = "Unlock All",
    Default = true,
    Tooltip = "Unlocks every skin, map, intro, death and victory in the inventory UI.",
    Callback = function(v)
        state.UnlockAll = v
        if v then
            unlockAll()
            if Window then
                Window:Notify({ Title = "Byte", Content = "All inventory unlocked.", Icon = "check" })
            end
        end
    end,
})

ThemeManager:SetLibrary(Window)
SaveManager:SetLibrary(Window)
ThemeManager:SetFolder("Byte/Dueling_Battle")
SaveManager:SetFolder("Byte/Dueling_Battle")
SaveManager:BuildConfigSection(Settings)
ThemeManager:ApplyToTab(Settings)

Settings:AddLeftGroupbox("Hub", "settings"):AddButton({
    Text = "Unload",
    DoubleClick = true,
    Tooltip = "Double-click to unload.",
    Callback = function()
        for _, c in ipairs(connections) do
            if typeof(c) == "RBXScriptConnection" then
                pcall(function() c:Disconnect() end)
            end
        end
        local h = getHandler()
        if h and parryBusy then h.IsParrying = nil end
        pcall(function() Library:Unload() end)
    end,
})

pcall(function() ThemeManager:LoadDefault() end)
pcall(function() SaveManager:LoadAutoloadConfig() end)

local skinCount = 0
for _ in pairs(savedSkins) do skinCount = skinCount + 1 end
local seqCount = 0
for _, k in ipairs({ "intro", "death", "victory" }) do
    if savedSeq[k] then seqCount = seqCount + 1 end
end

Window:Notify({
    Title = "Byte",
    Content = ("Loaded. %d skin%s + %d anim%s restored. Hook: %s"):format(
        skinCount, skinCount == 1 and "" or "s",
        seqCount, seqCount == 1 and "" or "s",
        hookOk and "OK" or ("FAIL - " .. tostring(hookErr))),
    Icon = "check",
})
