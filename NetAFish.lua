local repo = "https://raw.githubusercontent.com/viseamn/Visual/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "SaveManager.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Shared = require(ReplicatedStorage:WaitForChild("FishingShared"))
local DataCache = require(LocalPlayer.PlayerScripts:WaitForChild("DataCache"))

local Connections_Manager = {}

local state = {
  catch = false, reel = true, best = false, fuse = false,
  sell = false, sellEvery = 30, sellRarities = {}, keep_mutations = true,
  collect = false, collectEvery = 15, walkPads = false,
  meg = false, bloop = false, rebirth = false,
  net = false, skill = false, skillOnly = false, skillMain = "Net",
  potionBuy = false, potionUse = false, potion = false,
  arena = false,
  rIndex = false, rSpin = false, rOnline = false, rQuest = false, rPass = false,
  traits = false, traitEquip = true,
  afk = true,
  auto_equip_pet = false, auto_level_pet = false,
  auto_bm = false, auto_clam = false,
  auto_gear_equip = false, auto_gear_upgrade = false,
  skip_popups = false
}

local unloaded = false
local playerData
local bossActive = false
local lastRemoteError
local idleConnection

local Window = Library:CreateWindow({
  Title = "Byte",
  Layout = "Bottom bar",
  MenuKey = Enum.KeyCode.RightShift,
})

local FishTab = Window:AddTab("Fish", "fish")
local CoolerTab = Window:AddTab("Cooler", "package")
local UpgradeTab = Window:AddTab("Upgrade", "arrow-up")
local RewardTab = Window:AddTab("Reward", "gift")
local ArenaTab = Window:AddTab("Arena", "swords")
local PetsTab = Window:AddTab("Pets", "dog")
local SettingsTab = Window:CreateSettingsTab()

ThemeManager:SetLibrary(Window)
SaveManager:SetLibrary(Window)
ThemeManager:SetFolder("Byte")
SaveManager:SetFolder("Byte/NetAFish")
SaveManager:BuildConfigSection(SettingsTab)
ThemeManager:ApplyToTab(SettingsTab)
ThemeManager:LoadDefault()

local function teardown()
  unloaded = true
  if idleConnection then pcall(function() idleConnection:Disconnect() end) end
  for _, conn in pairs(Connections_Manager) do
    if typeof(conn) == "RBXScriptConnection" then pcall(function() conn:Disconnect() end) end
  end
  pcall(function()
    if Library.Unload then
      Library:Unload()
    elseif Library.Window then
      Library.Window:Destroy()
    else
      for _, gui in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
        if gui.Name:find("Viz") or gui.Name:find("Byte") then
          gui:Destroy()
        end
      end
    end
  end)
end

local function formatMoney(n)
  n = tonumber(n) or 0
  for _, tier in ipairs({
    { 1000000000000000, "Q" }, { 1000000000000, "T" }, { 1000000000, "B" },
    { 1000000, "M" }, { 1000, "K" }
  }) do
    if n >= tier[1] then
      return (("$%.2f%s"):format(n / tier[1], tier[2]):gsub("%.?0+([A-Z])$", "%1"))
    end
  end
  return "$" .. math.floor(n)
end

local function createStatusToggle(group, id, baseText, default, callback)
  local toggle = group:AddToggle(id, {
    Text = baseText,
    Default = default,
    Callback = function(v)
      if callback then callback(v) end
      if not v then
        pcall(function()
          local ctrl = toggle
          if group.GetControl then
            local ok, api = pcall(function() return group:GetControl(toggle) end)
            if ok and api then ctrl = api end
          end
          if ctrl and ctrl.SetText then ctrl:SetText(baseText) end
        end)
      end
    end,
  })
  
  local ctrl = toggle
  if group.GetControl then
    local ok, api = pcall(function() return group:GetControl(toggle) end)
    if ok and api then ctrl = api end
  end

  local function setStatus(status)
    if unloaded or not state[id] then return end
    pcall(function()
      local text = baseText .. " [" .. status .. "]"
      if ctrl and ctrl.SetText then ctrl:SetText(text)
      elseif toggle and toggle.SetText then toggle:SetText(text) end
    end)
  end
  return toggle, setStatus
end

local function loopTask(key, setText, interval, fn)
  task.spawn(function()
    while not unloaded do
      if state[key] then
        local ok, result = pcall(fn)
        if not ok and setText then setText("Error") end
      end
      task.wait(type(interval) == "function" and interval() or interval)
    end
  end)
end

local function getBase()
  local mapObj = workspace:FindFirstChild("Map")
  mapObj = mapObj and mapObj:FindFirstChild("Bases")
  for _, base in ipairs(mapObj and mapObj:GetChildren() or {}) do
    if base:GetAttribute("OwnerUserId") == LocalPlayer.UserId then return base end
  end
end

local function coolerAction(...)
  local args = { ... }
  return pcall(function() return Remotes.CoolerAction:InvokeServer(table.unpack(args)) end)
end

local function potionAction(...)
  local args = { ... }
  return pcall(function() return Remotes.Potions:InvokeServer(table.unpack(args)) end)
end

local function invokeRemote(name, ...)
  local remote = Remotes:FindFirstChild(name)
  if not remote then return false, name .. " missing" end
  local args = { ... }
  local ok, result = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
  if args[1] ~= "state" then
    if not ok then
      lastRemoteError = name .. " " .. tostring(args[1]) .. ": " .. tostring(result)
    elseif type(result) == "table" and (result.err or result.ok == false) then
      lastRemoteError = name .. " " .. tostring(args[1]) .. ": " .. tostring(result.err or result.msg or "ok=false")
    elseif result == nil or result == false then
      lastRemoteError = name .. " " .. tostring(args[1]) .. ": " .. tostring(result)
    end
  end
  return ok, result
end

local function claimStatus(count, key)
  local err = lastRemoteError
  lastRemoteError = nil
  local status = ("Claimed %d %s"):format(count, key)
  if err then status = status .. " (Err)" end
  return status
end

local function setValueById(id, value)
  pcall(function()
    local ctrl = (Library.Toggles and Library.Toggles[id]) or (Library.Options and Library.Options[id])
    if not ctrl then return end
    if ctrl.SetValue then ctrl:SetValue(value)
    elseif ctrl.Set then ctrl:Set(value) end
  end)
end

local function setupUpgradeGroup(name, icon, side)
  local group
  if side == "Right" then group = UpgradeTab:AddRightGroupbox(name, icon or "arrow-up")
  else group = UpgradeTab:AddLeftGroupbox(name, icon or "arrow-up") end
  local ids = {}
  local allId = "All_" .. name:gsub("%W", "")
  group:AddToggle(allId, {
    Text = "Upgrade All",
    Default = false,
    Callback = function(v)
      for _, id in ipairs(ids) do state[id] = v; setValueById(id, v) end
    end,
  })
  local function track(id) table.insert(ids, id) end
  return group, track
end

local function formatUpgrade(level, max, cost, lockMsg)
  local info = ("Lv %d / %d"):format(math.floor(level), math.floor(max))
  if level >= max then return info .. "  (MAX)", false end
  info = info .. "  •  next: " .. formatMoney(cost)
  if lockMsg then return info .. "  🔒 " .. tostring(lockMsg), false end
  return info, playerData and (playerData.Cash or 0) >= (cost or math.huge)
end

local function addBuyableToggle(group, track, id, name, infoFn, buyFn)
  local stateKey = "up_" .. id
  local toggle, setInfo = createStatusToggle(group, stateKey, name, false, function(v) state[stateKey] = v end)
  track(stateKey)
  task.spawn(function()
    while not unloaded do
      local ok, info, canBuy = pcall(infoFn)
      if ok then setInfo(info) end
      if ok and state[stateKey] and canBuy then pcall(buyFn); task.wait(0.8) end
      task.wait(state[stateKey] and 1 or 3)
    end
  end)
end

local function addAutoClaim(group, key, name, interval, fn)
  local toggle, setStatus = createStatusToggle(group, key, name, false, function(v) state[key] = v end)
  loopTask(key, setStatus, interval, function() setStatus(fn()) end)
end

idleConnection = LocalPlayer.Idled:Connect(function()
  if state.afk then
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
  end
end)

task.spawn(function()
  local toggle = false
  while not unloaded do
    task.wait(60)
    if state.afk then
      pcall(function()
        toggle = not toggle
        VirtualInputManager:SendMouseMoveEvent(toggle and 200 or 201, 200, game)
        if LocalPlayer:GetAttribute("AFKScreen") then
          VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
          VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
        end
      end)
    end
  end
end)

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
  if type(data) == "table" then
    DataCache.fix(data)
    playerData = data
  end
end)

task.spawn(function()
  local ok, result = pcall(function() return Remotes.GetData:InvokeServer() end)
  if ok and type(result) == "table" and not playerData then
    DataCache.fix(result)
    playerData = result
  end
end)

do
  local groupLeft = FishTab:AddLeftGroupbox("Fishing", "fish")
  local toggleCatch, setCatch = createStatusToggle(groupLeft, "catch", "Auto Catch Fish", false, function(v) state.catch = v end)
  local netCount = 0

  loopTask("catch", setCatch, 0.5, function()
    if bossActive then setCatch("Paused"); return end
    local base = getBase()
    local netState = base and base:GetAttribute("NetState")
    if not base then
      setCatch("Going home")
      Remotes.GoHome:FireServer()
      task.wait(3)
      return
    end
    if netState == "Idle" or netState == nil then
      Remotes.ThrowNet:FireServer()
      task.wait(1.3)
      if base:GetAttribute("NetState") == "Idle" then
        setCatch("Going home")
        Remotes.GoHome:FireServer()
        task.wait(3)
        return
      end
      netCount = netCount + 1
      setCatch(("Thrown (#%d)"):format(netCount))
    else
      setCatch(("Waiting (%s)"):format(tostring(netState)))
    end
  end)

  groupLeft:AddToggle("reel", {
    Text = "Auto Reel In when full",
    Default = true,
    Callback = function(v) state.reel = v end,
  })

  Remotes.NetFull.OnClientEvent:Connect(function()
    if state.catch and state.reel and not unloaded then
      pcall(function() Remotes.ReelIn:FireServer() end)
    end
  end)

  local groupMisc = FishTab:AddLeftGroupbox("Misc", "package")
  
  groupMisc:AddSlider("collectEvery", {
    Text = "Collect every (s)",
    Min = 5, Max = 120, Default = 15,
    Callback = function(v) state.collectEvery = v end,
  })

  groupMisc:AddToggle("walkPads", {
    Text = "Walk over pads",
    Default = false,
    Callback = function(v) state.walkPads = v end,
  })

  local toggleCollect, setCollect = createStatusToggle(groupMisc, "collect", "Auto Collect Cash", false, function(v) state.collect = v end)

  loopTask("collect", setCollect, function() return state.collectEvery end, function()
    local base = getBase()
    local pedestals = base and base:FindFirstChild("Pedestals")
    if not pedestals then setCollect("Not found"); return end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local savedCFrame = root and root.CFrame
    local count = 0
    for _, pedestal in ipairs(pedestals:GetChildren()) do
      if not state.collect then break end
      local slot = pedestal:GetAttribute("Slot")
      local collect = pedestal:FindFirstChild("Collect")
      collect = collect and collect:FindFirstChild("Pad")
      if slot ~= nil then
        if state.walkPads and root and collect then
          local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
          if humanoid then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
          end
          local look = root.CFrame.LookVector
          local target = collect.Position + Vector3.new(0, collect.Size.Y / 2 + 3, 0)
          root.CFrame = CFrame.lookAt(target, target + Vector3.new(look.X, 0, look.Z))
          root.AssemblyLinearVelocity = Vector3.zero
          root.AssemblyAngularVelocity = Vector3.zero
          task.wait(0.2)
        end
        Remotes.CollectPadReq:FireServer(slot)
        count = count + 1
        task.wait(0.1)
      end
    end
    if state.walkPads and root and savedCFrame then
      root.CFrame = savedCFrame
      root.AssemblyLinearVelocity = Vector3.zero
      root.AssemblyAngularVelocity = Vector3.zero
      local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
      if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        local s = humanoid:GetState()
        if s == Enum.HumanoidStateType.FallingDown or s == Enum.HumanoidStateType.Ragdoll then
          humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
      end
    end
    setCollect(("Collected %d"):format(count))
  end)

  groupMisc:AddToggle("afk", {
    Text = "Anti AFK",
    Default = true,
    Callback = function(v) state.afk = v end,
  })

  local toggleSkip, setSkipStatus = createStatusToggle(groupMisc, "skip_popups", "Auto-Skip Popups & Cutscenes", false, function(v) state.skip_popups = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.skip_popups then
        pcall(function()
          if LocalPlayer:GetAttribute("Set_Cutscenes") ~= false then LocalPlayer:SetAttribute("Set_Cutscenes", false) end
          if LocalPlayer:GetAttribute("Set_Flashes") ~= false then LocalPlayer:SetAttribute("Set_Flashes", false) end
          local camera = workspace.CurrentCamera
          if camera and camera.CameraType == Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Custom end
          
          local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
          if playerGui then
            for _, gui in ipairs(playerGui:GetChildren()) do
              if gui:IsA("ScreenGui") and gui.Enabled then
                local isOurUI = (gui.Name == "CoolerUI" or gui.Name == "UpgradeMenuUI" or gui.Name == "PetsUI" or gui.Name == "BlackMarketUI" or gui.Name == "PearlShopUI" or gui.Name == "GearUI" or gui.Name == "RebirthUI")
                if not isOurUI then
                  for _, desc in ipairs(gui:GetDescendants()) do
                    if (desc:IsA("TextButton") or desc:IsA("ImageButton")) and desc.Visible then
                      local txt = string.lower(desc.Text or "")
                      if txt:find("awesome") or txt:find("collect") or txt:find("continue") or txt:find("okay") or txt == "ok" or txt:find("close") or txt:find("claim") or txt:find("skip") or txt:find("next") or txt:find("yes") or txt:find("confirm") or txt:find("accept") or desc.Name == "RollContinue" or desc.Name == "UnlocksOk" then
                        pcall(function() desc.MouseButton1Click:Fire() end)
                      end
                    end
                  end
                end
              end
            end
          end
        end)
      end
      task.wait(0.1)
    end
  end)

  local groupRight = FishTab:AddRightGroupbox("Events", "crosshair")
  groupRight:AddLabel("Kraken: keep Auto Catch on — your net in the water damages it")

  local megJoined = false
  local megCount = 0
  local toggleMeg, setMeg = createStatusToggle(groupRight, "meg", "Auto Shoot Megalodon", false, function(v)
    state.meg = v
    if not v and megJoined then
      pcall(function() Remotes.MegEvent:FireServer("leave") end)
      megJoined = false
      bossActive = false
    end
  end)

  loopTask("meg", setMeg, 0.3, function()
    local meg = Shared.Megalodon or {}
    local active = workspace:GetAttribute("MegActive") == true
    if not active then
      if megJoined then
        pcall(function() Remotes.MegEvent:FireServer("leave") end)
        megJoined = false
      end
      bossActive = false
      setMeg("Waiting")
      return
    end
    if playerData and (playerData.Rebirths or 0) < (meg.NeedRebirth or 0) then
      setMeg(("🔒 Reb %d"):format(meg.NeedRebirth))
      return
    end
    bossActive = true
    if not megJoined then
      Remotes.MegEvent:FireServer("enter")
      megJoined = true
      task.wait(1)
    end
    local localModel = workspace:FindFirstChild("MegalodonLocal")
    local model = localModel and localModel:FindFirstChild("Megalodon")
    if not model then
      setMeg("Not found")
      return
    end
    local ok, pos = pcall(function()
      return model:IsA("BasePart") and model.Position or model:GetPivot().Position
    end)
    if not ok then return end
    Remotes.MegEvent:FireServer("fire", pos)
    megCount = megCount + 1
    setMeg(("Shooting (%d)"):format(megCount))
    task.wait(math.max(meg.Cooldown or 2, 0.5) + 0.05)
  end)

  local bloopJoined = false
  local bloopCount = 0
  local toggleBloop, setBloop = createStatusToggle(groupRight, "bloop", "Auto Shoot Bloop", false, function(v)
    state.bloop = v
    if not v and bloopJoined then
      pcall(function() Remotes.BloopEvent:FireServer("leave") end)
      bloopJoined = false
      bossActive = false
    end
  end)

  loopTask("bloop", setBloop, 0.3, function()
    local bloop = Shared.Bloop or {}
    if workspace:GetAttribute("BloopActive") ~= true then
      if bloopJoined then
        pcall(function() Remotes.BloopEvent:FireServer("leave") end)
        bloopJoined = false
      end
      if not (state.meg and workspace:GetAttribute("MegActive") == true) then
        bossActive = false
      end
      setBloop("Waiting")
      return
    end
    if playerData and (playerData.Rebirths or 0) < (bloop.NeedRebirth or 0) then
      setBloop(("🔒 Reb %d"):format(bloop.NeedRebirth))
      return
    end
    bossActive = true
    if not bloopJoined then
      Remotes.BloopEvent:FireServer("enter")
      bloopJoined = true
      task.wait(1)
    end
    local elapsed = workspace:GetServerTimeNow() -
      (workspace:GetAttribute("BloopStart") or workspace:GetServerTimeNow())
    local ok, pos = pcall(function() return Shared.BloopPos(elapsed) end)
    if not (ok and typeof(pos) == "Vector3") then
      setBloop("Pos unknown")
      return
    end
    Remotes.BloopEvent:FireServer("fire", pos)
    bloopCount = bloopCount + 1
    setBloop(("Shooting (%d)"):format(bloopCount))
    task.wait(math.max(bloop.Cooldown or 2, 0.5) + 0.05)
  end)

  local toggleRebirth, setRebirth = createStatusToggle(groupRight, "rebirth", "Auto Rebirth", false, function(v) state.rebirth = v end)

  loopTask("rebirth", setRebirth, 5, function()
    if not playerData then setRebirth("Waiting"); return end
    local canRebirth, info = Shared.CanRebirth(playerData)
    if canRebirth then
      Remotes.RebirthRequest:FireServer()
      setRebirth("Rebirthed")
      task.wait(3)
    elseif info then
      setRebirth(("Need %s"):format(formatMoney(info.Cash)))
    end
  end)
end

do
  local groupLeft = CoolerTab:AddLeftGroupbox("Cooler", "package")

  local toggleBest, setBest = createStatusToggle(groupLeft, "best", "Auto Equip Best", false, function(v) state.best = v end)
  loopTask("best", setBest, 20, function()
    Remotes.BestSetup:FireServer()
    setBest("Equipped")
  end)

  local toggleFuse, setFuse = createStatusToggle(groupLeft, "fuse", "Auto Fuse All", false, function(v) state.fuse = v end)
  loopTask("fuse", setFuse, 15, function()
    local ok, result = coolerAction("fuseAll")
    if ok and type(result) == "table" and result.ok then setFuse("Fused")
    else setFuse("Nothing") end
  end)

  local rarityOptions = {}
  for _, rarity in ipairs(Shared.Rarities) do table.insert(rarityOptions, rarity.Name) end

  groupLeft:AddDropdown("sellRarities", {
    Text = "Sell these rarities",
    Values = rarityOptions,
    Multi = true,
    Default = {},
    Callback = function(v)
      state.sellRarities = {}
      if type(v) == "table" then
        for name, selected in pairs(v) do
          if selected then state.sellRarities[name] = true end
        end
      elseif type(v) == "string" then
        state.sellRarities[v] = true
      end
    end,
  })

  groupLeft:AddToggle("keep_mutations", {
    Text = "Keep Mutated Fish (Never Sell)",
    Default = true,
    Callback = function(v) state.keep_mutations = v end,
  })

  groupLeft:AddSlider("sellEvery", {
    Text = "Sell every (s)",
    Min = 5, Max = 300, Default = 30,
    Callback = function(v) state.sellEvery = v end,
  })

  local toggleSell, setSell = createStatusToggle(groupLeft, "sell", "Auto Sell", false, function(v) state.sell = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.sell then
        if not playerData or not playerData.Cooler then
          local ok, res = pcall(function() return Remotes.GetData:InvokeServer() end)
          if ok and type(res) == "table" then
            DataCache.fix(res)
            playerData = res
          end
        end

        if playerData and playerData.Cooler then
          local toSell = {}
          for key, item in pairs(playerData.Cooler) do
            local species = Shared.SpeciesById[item.s]
            if species then
              local rarityName = Shared.Rarities[species.Rarity].Name
              local free = Shared.CoolerFree and Shared.CoolerFree(item) or 0
              
              if state.sellRarities[rarityName] and free > 0 then
                if not (state.keep_mutations and item.mu ~= nil and item.mu ~= "") then
                  table.insert(toSell, key)
                end
              end
            end
          end
          
          if #toSell > 0 then
            local success = false
            local sellRemote = Remotes:FindFirstChild("SellFish")
            if sellRemote then
              local sOk, sRes = pcall(function() return sellRemote:InvokeServer(toSell) end)
              if sOk then success = true end
            end
            if not success then
              local cOk, cRes = coolerAction("releaseMany", toSell)
              if cOk and (cRes == nil or cRes == true or type(cRes) == "table" and cRes.ok ~= false) then
                success = true
              end
            end
            
            if success then setSell(("Sold %d"):format(#toSell))
            else setSell("Failed") end
          else
            setSell("Nothing to sell")
          end
          task.wait(state.sellEvery)
        else
          setSell("Waiting for data")
          task.wait(1)
        end
      else
        task.wait(1)
      end
    end
  end)

  local groupRight = CoolerTab:AddRightGroupbox("Potions", "flask-conical")
  local bought, used = 0, 0

  local togglePotion, setPotion = createStatusToggle(groupRight, "potionBuy", "Auto Buy Potions", false, function(v)
    state.potionBuy = v
    state.potion = state.potionBuy or state.potionUse
  end)

  groupRight:AddToggle("potionUse", {
    Text = "Auto Use Potions",
    Default = false,
    Callback = function(v)
      state.potionUse = v
      state.potion = state.potionBuy or state.potionUse
    end,
  })

  loopTask("potion", setPotion, 10, function()
    if state.potionBuy then
      local ok, result = potionAction("state")
      if ok and type(result) == "table" then
        for i, item in ipairs(result.stock or {}) do
          if type(item) == "table" and not item.bought then
            local buyOk, buyRes = potionAction("buy", i)
            if buyOk and type(buyRes) == "table" and buyRes.ok then bought = bought + 1 end
            task.wait(0.4)
          end
        end
      end
    end
    if state.potionUse then
      local ok, result = potionAction("useAll")
      if ok and result ~= false and not (type(result) == "table" and result.ok == false) then used = used + 1 end
    end
    setPotion(("Bought %d • Used %d"):format(bought, used))
  end)
end

do
  local group = UpgradeTab:AddLeftGroupbox("Nets", "anchor")
  local toggleNet, setNetInfo = createStatusToggle(group, "net", "Auto Buy Next Net", false, function(v) state.net = v end)

  task.spawn(function()
    while not unloaded do
      local tier = playerData and playerData.NetTier or 1
      local nextNet = Shared.Nets[tier + 1]
      local info = ("Tier %d • %s"):format(tier, tostring(Shared.Nets[tier] and Shared.Nets[tier].Name or tier))
      local canBuy = false
      if nextNet then
        local rebirthOk = true
        if Shared.NetRebirthOk then
          rebirthOk = Shared.NetRebirthOk(playerData or {}, tier + 1)
        end
        info = info .. " • " .. formatMoney(nextNet.Cost)
        canBuy = rebirthOk and playerData and (playerData.Cash or 0) >= (nextNet.Cost or math.huge)
      else
        info = info .. " (MAX)"
      end
      setNetInfo(info)
      if state.net and canBuy then
        pcall(function() Remotes.BuyItem:FireServer("Net", tier + 1) end)
        task.wait(1)
      end
      task.wait(state.net and 1 or 3)
    end
  end)
end

do
  local ok, skillTree = pcall(function()
    return require(ReplicatedStorage:WaitForChild("SkillTree", 10))
  end)
  if ok and skillTree and skillTree.Nodes then
    local group, track = setupUpgradeGroup("Skill Tree", "git-branch", "Left")
    local branchOptions = {}
    for _, branch in ipairs(skillTree.Branches or {}) do
      table.insert(branchOptions, branch.Id)
    end
    state.skillMain = branchOptions[1]
    group:AddDropdown("skillMain", {
      Text = "Main branch",
      Values = branchOptions,
      Default = state.skillMain,
      Callback = function(v) state.skillMain = type(v) == "table" and v[1] or v end,
    })
    group:AddToggle("skillOnly", {
      Text = "Only main branch",
      Default = false,
      Callback = function(v) state.skillOnly = v end,
    })
    local toggleSkill, setInfo = createStatusToggle(group, "skill", "Auto Skill Tree", false, function(v) state.skill = v end)
    track("skill")
    
    local function orderedNodes()
      local list = {}
      local order = { state.skillMain }
      if not state.skillOnly then
        for _, id in ipairs(branchOptions) do
          if id ~= state.skillMain then table.insert(order, id) end
        end
      end
      for _, id in ipairs(order) do
        local copy = table.clone(skillTree.ByBranch[id] or {})
        table.sort(copy, function(a, b) return (a.Order or 0) < (b.Order or 0) end)
        for _, node in ipairs(copy) do table.insert(list, node) end
      end
      return list
    end

    task.spawn(function()
      while not unloaded do
        local pcallOk, result = pcall(function()
          if not playerData then setInfo("Waiting"); return end
          local free = skillTree.free(playerData)
          local nextNode, lockedMsg
          for _, node in ipairs(orderedNodes()) do
            local canBuy, reason = skillTree.canBuy(playerData, node.Id)
            if canBuy then nextNode = node; break end
            if not lockedMsg and reason ~= "Maxed" then lockedMsg = reason end
          end
          setInfo(("Pts: %d • "):format(math.floor(free)) .. (nextNode and "Ready" or "Maxed/Locked"))
          if state.skill and nextNode then
            Remotes.SkillTree:InvokeServer("buy", nextNode.Id)
            task.wait(0.6)
          end
        end)
        task.wait(state.skill and 1 or 4)
      end
    end)
  end
end

for _, tabName in ipairs(Shared.UpgradeTabs or { "Nets", "Fishing", "Market" }) do
  if tabName ~= "Nets" then
    local group, track = setupUpgradeGroup(tabName, "arrow-up", "Left")
    for _, upgrade in ipairs(Shared.Upgrades) do
      if upgrade.Tab == tabName and not upgrade.Hidden then
        local id = "up_" .. upgrade.Id
        local toggle, setInfo = createStatusToggle(group, id, upgrade.Name or upgrade.Id, false, function(v) state[id] = v end)
        track(id)
        task.spawn(function()
          while not unloaded do
            local level = playerData and playerData.Upgrades and playerData.Upgrades[upgrade.Id] or 0
            local info = ("Lv %d / %d"):format(math.floor(level), math.floor(upgrade.Max or 0))
            local canBuy = false
            if level >= (upgrade.Max or 0) then
              info = info .. " (MAX)"
            elseif playerData then
              local cost = Shared.UpgradeCost(upgrade.Id, level)
              local levelOk = true
              if Shared.UpgradeLevelOk then
                levelOk = Shared.UpgradeLevelOk(playerData, upgrade, level + 1)
              end
              info = info .. " • " .. formatMoney(cost)
              canBuy = levelOk and (playerData.Cash or 0) >= (cost or math.huge)
            end
            setInfo(info)
            if state[id] and canBuy then
              pcall(function() Remotes.BuyItem:FireServer("Upgrade", upgrade.Id) end)
              task.wait(0.8)
            end
            task.wait(state[id] and 1 or 3)
          end
        end)
      end
    end
  end
end

if Shared.Spear and Shared.Spear.Upgrades then
  local group, track = setupUpgradeGroup("Spear Gun", "crosshair", "Right")
  for _, upgrade in ipairs(Shared.Spear.Upgrades) do
    addBuyableToggle(group, track, "Spear_" .. upgrade.Id, upgrade.Name or upgrade.Id, function()
      local level = playerData and (playerData.Spear or {})[upgrade.Id] or 0
      local levelOk = true
      if playerData and Shared.HelperLevelOk then
        levelOk = Shared.HelperLevelOk(playerData, upgrade, level + 1)
      end
      return formatUpgrade(level, upgrade.Max or 0, Shared.SpearCost(upgrade.Id, level), not levelOk and "Locked" or nil)
    end, function()
      Remotes.SpearAction:InvokeServer("buy", upgrade.Id)
    end)
  end
end

if Shared.Helper and Shared.Helper.Upgrades then
  local group, track = setupUpgradeGroup("Fisherman", "user", "Right")
  for _, upgrade in ipairs(Shared.Helper.Upgrades) do
    addBuyableToggle(group, track, "Helper_" .. upgrade.Id, upgrade.Name or upgrade.Id, function()
      local level = playerData and (playerData.Helper or {})[upgrade.Id] or 0
      local levelOk = true
      if playerData and Shared.HelperLevelOk then
        levelOk = Shared.HelperLevelOk(playerData, upgrade, level + 1)
      end
      return formatUpgrade(level, upgrade.Max or 0, Shared.HelperCost(upgrade.Id, level), not levelOk and "Locked" or nil)
    end, function()
      Remotes.HelperAction:InvokeServer("buy", upgrade.Id)
    end)
  end
end

if Shared.Boat and Shared.Boat.Hulls then
  local group, track = setupUpgradeGroup("Boat", "ship", "Right")
  addBuyableToggle(group, track, "Boat_Hull", "Boat (Hull)", function()
    local hull = playerData and type(playerData.Boat) == "table" and playerData.Boat.Hull or 0
    local nextHull = Shared.Boat.Hulls[hull + 1]
    local currentHull = Shared.Boat.Hulls[hull]
    local info = ("Boat: %s"):format(currentHull and currentHull.Name or "-")
    if not nextHull then return info .. " (MAX)", false end
    info = info .. " • " .. formatMoney(nextHull.Cost)
    if playerData and (playerData.Rebirths or 0) < (nextHull.Rebirth or 0) then
      return info .. " 🔒", false
    end
    return info, playerData and (playerData.Cash or 0) >= nextHull.Cost
  end, function()
    Remotes.BoatAction:InvokeServer("buy", "Hull")
  end)
  for _, upgrade in ipairs(Shared.Boat.Upgrades or {}) do
    addBuyableToggle(group, track, "Boat_" .. upgrade.Id, upgrade.Name or upgrade.Id, function()
      local boat = playerData and type(playerData.Boat) == "table" and playerData.Boat or {}
      local hull = boat.Hull or 0
      local level = boat[upgrade.Id] or 0
      local max = upgrade.Extra and (upgrade.Max or 0) or Shared.BoatMaxLevel and Shared.BoatMaxLevel(hull) or upgrade.Max or 0
      local lockMsg
      if hull <= 0 then lockMsg = "No boat" end
      return formatUpgrade(level, max, Shared.BoatCost(upgrade.Id, level), lockMsg)
    end, function()
      Remotes.BoatAction:InvokeServer("buy", upgrade.Id)
    end)
  end
end

do
  local groupRight = UpgradeTab:AddRightGroupbox("Gear", "shield")
  local toggleGearEquip, setGearEquipStatus = createStatusToggle(groupRight, "auto_gear_equip", "Auto Equip Best Gear", false, function(v) state.auto_gear_equip = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.auto_gear_equip then
        local ok, res = pcall(function() return Remotes.Gear:InvokeServer("state") end)
        if ok and type(res) == "table" and res.state and res.state.gear then
          local gear = res.state.gear
          local best = {}
          for _, item in ipairs(gear.Inv or {}) do
            local tier = item.t or 1
            local lv = item.l or 0
            local slot = item.s
            local score = tier * 100 + lv
            if not best[slot] or score > best[slot].score then
              best[slot] = { uuid = item.u, score = score }
            end
          end
          for slot, data in pairs(best) do
            if gear.Eq[slot] ~= data.uuid then
              pcall(function() Remotes.Gear:InvokeServer("equip", data.uuid) end)
              task.wait(0.5)
            end
          end
          setGearEquipStatus("Equipped")
        end
      end
      task.wait(state.auto_gear_equip and 5 or 3)
    end
  end)

  local toggleGearUpgrade, setGearUpgradeStatus = createStatusToggle(groupRight, "auto_gear_upgrade", "Auto Upgrade Gear", false, function(v) state.auto_gear_upgrade = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.auto_gear_upgrade then
        local ok, res = pcall(function() return Remotes.Gear:InvokeServer("state") end)
        if ok and type(res) == "table" and res.state and res.state.gear then
          local gear = res.state.gear
          local upgraded = false
          for slot, uuid in pairs(gear.Eq or {}) do
             local upOk, upRes = pcall(function() return Remotes.Gear:InvokeServer("upgrade", uuid) end)
             if upOk and type(upRes) == "table" and upRes.ok then
               upgraded = true
               setGearUpgradeStatus("Upgraded")
               task.wait(1)
             end
          end
          if not upgraded then setGearUpgradeStatus("Max/No Mats") end
        end
      end
      task.wait(state.auto_gear_upgrade and 10 or 5)
    end
  end)
end

do
  local groupLeft = RewardTab:AddLeftGroupbox("Rewards", "gift")

  addAutoClaim(groupLeft, "rIndex", "Auto Claim Index", 30, function()
    local count = 0
    local ok, result = invokeRemote("Rewards", "index")
    if ok and type(result) == "table" then
      for key, entry in pairs(result) do
        if type(entry) == "table" and entry.claimable then
          invokeRemote("Rewards", "claimIndex", key)
          count = count + 1
          task.wait(0.3)
        end
      end
    end
    for i = 1, #Shared.Rarities do
      local pageOk, pageRes = pcall(function() return Remotes.Rewards:InvokeServer("claimPage", i) end)
      if pageOk and type(pageRes) == "table" and pageRes.ok then count = count + 1 end
    end
    lastRemoteError = nil
    return claimStatus(count, "Index")
  end)

  addAutoClaim(groupLeft, "rSpin", "Auto Spin", 10, function()
    local ok, result = invokeRemote("Retention", "state")
    local spin = ok and type(result) == "table" and (type(result.spin) == "table" and result.spin or result) or {}
    local available = tonumber(spin.spins) or 0
    local count = 0
    while state.rSpin and available > 0 and count < 20 do
      invokeRemote("Retention", "spin")
      count = count + 1
      available = available - 1
      task.wait(2)
    end
    return claimStatus(count, "Spins")
  end)

  addAutoClaim(groupLeft, "rOnline", "Auto Claim Online Gifts + Daily", 20, function()
    local count = 0
    local ok, result = invokeRemote("Rewards", "state")
    if ok and type(result) == "table" then
      for key, gift in pairs(result.gifts or {}) do
        if type(gift) == "table" and gift.ready and not gift.claimed then
          invokeRemote("Rewards", "claimGift", key)
          count = count + 1
          task.wait(0.3)
        end
      end
    end
    local dailyOk, dailyRes = invokeRemote("Rewards", "claimDaily")
    if dailyOk and type(dailyRes) == "table" and dailyRes.ok then count = count + 1 end
    return claimStatus(count, "Gifts")
  end)

  addAutoClaim(groupLeft, "rQuest", "Auto Claim Quests", 15, function()
    local count = 0
    local ok, result = invokeRemote("Contracts", "state")
    if ok and type(result) == "table" then
      for i, contract in ipairs(result.list or {}) do
        if type(contract) == "table" and contract.k ~= "wait" and not contract.claimed and (contract.p or 0) >= (contract.goal or math.huge) then
          local claimOk, claimRes = invokeRemote("Contracts", "claim", i)
          if claimOk and claimRes ~= false then count = count + 1 end
          task.wait(0.4)
        end
      end
    end
    local challengeOk, challengeRes = invokeRemote("Challenge", "state")
    if challengeOk and type(challengeRes) == "table" then
      for i, tier in ipairs(challengeRes.tiers or {}) do
        if type(tier) == "table" and tier.done and not tier.claimed then
          invokeRemote("Challenge", "claim", i)
          count = count + 1
          task.wait(0.4)
        end
      end
    end
    return claimStatus(count, "Quests")
  end)

  local toggleClam, setClamStatus = createStatusToggle(groupLeft, "auto_clam", "Auto Free Daily Clam", false, function(v) state.auto_clam = v end)
  task.spawn(function()
    while not unloaded do
      if state.auto_clam then
        local ok, res = pcall(function() return Remotes.PearlShop:InvokeServer("freeClam") end)
        if ok and type(res) == "table" and res.ok then setClamStatus("Claimed")
        else setClamStatus("Already claimed") end
      end
      task.wait(state.auto_clam and 60 or 10)
    end
  end)

  local groupRight = RewardTab:AddRightGroupbox("Codes", "key")
  local function notify(title, text)
    pcall(function() Window:Notify({ Title = title, Content = text, Icon = "check" }) end)
  end

  groupRight:AddButton({
    Text = "Redeem All Codes",
    Callback = function()
      task.spawn(function()
        local codes, seen = {}, {}
        local function addCode(code)
          code = tostring(code):upper()
          if code ~= "" and not seen[code] then
            seen[code] = true
            table.insert(codes, code)
          end
        end
        local ok, result = pcall(function() return require(ReplicatedStorage:WaitForChild("UpdateLog", 5)) end)
        local function scan(tbl, depth)
          if depth > 6 or type(tbl) ~= "table" then return end
          for k, v in pairs(tbl) do
            if k == "code" and type(v) == "string" then addCode(v)
            elseif type(v) == "string" then
              for match in v:gmatch("CODE ([%w_]+):") do addCode(match) end
            else scan(v, depth + 1) end
          end
        end
        if ok then scan(result, 0) end
        local count = 0
        for _, code in ipairs(codes) do
          local rOk, rRes = invokeRemote("Rewards", "redeem", code)
          if rOk and (rRes == true or type(rRes) == "table" and rRes.ok) then count = count + 1 end
          task.wait(1)
        end
        notify("Codes", ("Redeemed %d / %d codes"):format(count, #codes))
      end)
    end,
  })

  local groupTraits = RewardTab:AddRightGroupbox("Traits", "sparkles")
  local toggleTraits, setTraitStatus = createStatusToggle(groupTraits, "traits", "Auto Roll Traits", false, function(v) state.traits = v end)

  loopTask("traits", setTraitStatus, 5, function()
    local ok, result = invokeRemote("Traits", "state")
    if not (ok and type(result) == "table") then setTraitStatus("Waiting"); return end
    
    local function getRolls(data)
        local r = tonumber(data.rolls)
        if r and r > 0 then return r end
        local t = tonumber(data.traits)
        if t and t > 0 then return t end
        local o = tonumber(data.ownedRolls)
        if o and o > 0 then return o end
        return 0
    end
    
    local currentRolls = getRolls(result)
    local total = 0
    
    while state.traits and currentRolls > 0 do
      local batch = currentRolls >= 10 and 10 or 1
      local rollOk, rollRes = invokeRemote("Traits", "roll", batch)
      if not rollOk or (type(rollRes) == "table" and rollRes.err) then
          setTraitStatus("Roll Failed")
          break
      end
      total = total + batch
      task.wait(4)
      local updateOk, update = invokeRemote("Traits", "state")
      if not (updateOk and type(update) == "table") then break end
      result = update
      currentRolls = getRolls(result)
    end
    
    local best = 0
    for _, owned in ipairs(result.owned or {}) do
      local n = tonumber(owned)
      if n and n > best then best = n end
    end
    if state.traitEquip and best > 0 and result.trait ~= best then
      invokeRemote("Traits", "equip", best)
    end
    setTraitStatus(("Tier %s • Rolls %d"):format(tostring(best), currentRolls))
  end)

  groupTraits:AddToggle("traitEquip", {
    Text = "Auto Equip Best Trait",
    Default = true,
    Callback = function(v) state.traitEquip = v end,
  })

  local groupPass = RewardTab:AddRightGroupbox("Season Pass", "award")
  local togglePass, setPassStatus = createStatusToggle(groupPass, "rPass", "Auto Claim Season Pass", false, function(v) state.rPass = v end)

  loopTask("rPass", setPassStatus, 20, function()
    local ok, result = invokeRemote("SeasonPass", "state")
    if not (ok and type(result) == "table") then setPassStatus("Waiting"); return end
    local count = 0
    for tier = 1, result.tier or 0 do
      if not (result.free or {})[tostring(tier)] then
        invokeRemote("SeasonPass", "claim", { tier = tier, gold = false })
        count = count + 1
        task.wait(0.4)
      end
      if result.vip and not (result.gold or {})[tostring(tier)] then
        invokeRemote("SeasonPass", "claim", { tier = tier, gold = true })
        count = count + 1
        task.wait(0.4)
      end
    end
    setPassStatus(claimStatus(count, "Pass"))
  end)

  local toggleBM, setBMStatus = createStatusToggle(groupPass, "auto_bm", "Auto Buy Black Market", false, function(v) state.auto_bm = v end)
  task.spawn(function()
    while not unloaded do
      if state.auto_bm then
        local ok, res = pcall(function() return Remotes.BlackMarket:InvokeServer("state") end)
        if ok and type(res) == "table" and res.items then
          local bought = 0
          for _, item in ipairs(res.items) do
            if not item.bought and (res.cash or 0) >= item.price then
              local buyOk = pcall(function() Remotes.BlackMarket:InvokeServer("buy", item.id) end)
              if buyOk then bought = bought + 1 end
              task.wait(1)
            end
          end
          if bought > 0 then setBMStatus("Bought " .. bought)
          else setBMStatus("Waiting") end
        end
      end
      task.wait(state.auto_bm and 10 or 5)
    end
  end)
end

do
  local ok, arenaLib = pcall(function() return require(ReplicatedStorage:WaitForChild("Arena", 10)) end)
  local group = ArenaTab:AddLeftGroupbox("Arena", "swords")
  local toggleArena, setArenaStatus = createStatusToggle(group, "arena", "Auto Arena", false, function(v) state.arena = v end)
  local arenaWins = 0

  local function arenaInvoke(...)
    local args = { ... }
    local invokeOk, result = pcall(function() return Remotes.Arena:InvokeServer(table.unpack(args)) end)
    return invokeOk and type(result) == "table" and result or nil
  end

  loopTask("arena", setArenaStatus, 3, function()
    if not ok or not arenaLib then setArenaStatus("Not found"); return end
    local currentState = arenaInvoke("state")
    if not currentState then setArenaStatus("Waiting"); return end
    local sorted = arenaLib.sortTeam(Shared, currentState.show or {})
    local teamUids, currentTeam = {}, {}
    for i = 1, math.min(3, #sorted) do
      if sorted[i].uid then table.insert(teamUids, sorted[i].uid) end
    end
    for _, member in ipairs(currentState.team or {}) do currentTeam[member.uid] = true end
    local teamMatches = #teamUids == #(currentState.team or {})
    for _, uid in ipairs(teamUids) do
      if not currentTeam[uid] then teamMatches = false; break end
    end
    if #teamUids == 0 then setArenaStatus("Empty showcase"); return end
    if not teamMatches then
      currentState = arenaInvoke("team", teamUids) or currentState
      task.wait(1)
    end
    if (currentState.left or 0) <= 0 then setArenaStatus("No battles left"); return end
    local team = currentState.team or sorted
    local target
    for _, opponent in ipairs(currentState.opps or {}) do
      local battleOk, battle = pcall(arenaLib.battle, Shared, team, opponent.f or {})
      if battleOk and battle and battle.win then target = opponent; break end
    end
    if target then
      local fightResult = arenaInvoke("fight", target.i)
      if fightResult and fightResult.battle then arenaWins = arenaWins + 1 end
      setArenaStatus(("Fought • Left %d"):format(fightResult and fightResult.left or 0))
      task.wait(2)
    elseif (currentState.refreshIn or 0) <= 0 then
      arenaInvoke("refresh")
      setArenaStatus("Refreshed")
    else
      setArenaStatus(("Refresh in %ds"):format(math.floor(currentState.refreshIn)))
    end
  end)
end

do
  local group = PetsTab:AddLeftGroupbox("Pets", "dog")
  
  local function getPetState()
    local ok, res = pcall(function() return Remotes.Pets:InvokeServer("state") end)
    if ok and type(res) == "table" then return res end
  end

  local toggleEquip, setEquipStatus = createStatusToggle(group, "auto_equip_pet", "Auto Equip Best Pet", false, function(v) state.auto_equip_pet = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.auto_equip_pet then
        local data = getPetState()
        if data and data.pets then
          local bestPet, bestScore = nil, -1
          for id, count in pairs(data.pets) do
            if count > 0 then
              local petInfo = Shared.PetById[id]
              if petInfo then
                local lv = data.lv and data.lv[id] or 1
                local mult = Shared.PetMultAt(petInfo, lv)
                if mult > bestScore then bestScore = mult; bestPet = id end
              end
            end
          end
          if bestPet and data.equip ~= bestPet then
             pcall(function() Remotes.Pets:InvokeServer("equip", bestPet) end)
             setEquipStatus("Equipped")
          end
        end
      end
      task.wait(state.auto_equip_pet and 5 or 3)
    end
  end)

  local toggleLevel, setLevelStatus = createStatusToggle(group, "auto_level_pet", "Auto Level Best Pet", false, function(v) state.auto_level_pet = v end)
  
  task.spawn(function()
    while not unloaded do
      if state.auto_level_pet then
        local data = getPetState()
        if data and data.pets then
           local target, maxCount = nil, 1
           for id, count in pairs(data.pets) do
             if count > 1 then
                local lv = data.lv and data.lv[id] or 1
                if lv < Shared.PetMaxLevel then
                   if count > maxCount then maxCount = count; target = id end
                end
             end
           end
           if target then
              local ok = pcall(function() Remotes.Pets:InvokeServer("levelUp", target) end)
              if ok then setLevelStatus("Leveled") end
           else
              setLevelStatus("No pets to level")
           end
        end
      end
      task.wait(state.auto_level_pet and 2 or 5)
    end
  end)
end

do
  local NR_Enabled = false
  local NR_Gen = 0
  local NR_Store = {}
  local NR_Pinned = {}
  local NR_HIDDEN = { Decoration = true }
  local NR_Terrain = workspace.Terrain
  local NR_Render = nil
  pcall(function() NR_Render = settings().Rendering end)
  local NR_HiddenParts = {}
  local NR_HiddenGuis2 = {}
  local NR_HiddenGuis = {}
  local NR_LightingSeen = {}
  local NR_ZERO_LIFETIME = NumberRange.new(0)

  NR_Pinned[Lighting] = true
  NR_Pinned[NR_Terrain] = true
  if NR_Render then NR_Pinned[NR_Render] = true end

  local NR_MAP_FOLDER_NAMES = {
      Map=true,LobbySpawnPlate=true,Spawn=true,Leaderboards=true,
      Drones=true,ZombieCrownClash=true,PixelKillEvent=true,
      SummerEventBB=true,FriendCrate=true,MapBounds=true,
  }
  local NR_DIRECT_WORKSPACE_PARTS = { FakeSky=true }
  local NR_LOBBY_GUI_NAMES = {
      LobbyTickets=true,LobbyLTMPack=true,LobbyJoinIssue=true,
      MobileLobbyPrompt=true,ServerBrowser=true,ServerBrowserOld=true,
      ServerSelection=true,ServerSelectionNew=true,ChooseMap=true,
      MapSelector=true,RankedQueue=true,RankedSelection=true,
      MatchFound=true,ChooserUI=true,WaitingScreen=true,
      TournamentWaiting=true,CutsceneWaiting=true,spawnTut=true,
  }
  local NR_LIGHTING = {
      GlobalShadows=false,Brightness=1,ClockTime=14,
      ExposureCompensation=0,EnvironmentDiffuseScale=0,
      EnvironmentSpecularScale=0,FogStart=math.huge,FogEnd=math.huge,
      ShadowSoftness=0,
      Ambient=Color3.fromRGB(70,70,70),
      OutdoorAmbient=Color3.fromRGB(70,70,70),
  }
  local NR_CONNECTIONS = {
      'NR_Descendant','NR_DescDrain','NR_LightingChild','NR_LightingProp',
      'NR_Runtime','NR_MapDescendant','NR_GuiAdded','NR_GraySkyForce','NR_MapChanged','NR_MapRemoved','NR_MatchCheck',
  }

  local NR_WEAPON_NAMES = {
      Weapons = true, Weapon = true, Gun = true, Guns = true,
      ViewModel = true, Viewmodel = true, viewmodel = true,
      FPArms = true, FPSArms = true, Arms = true, ArmsFolder = true,
      Tool = true, Tools = true, EquippedTool = true, EquippedTools = true,
      Firearm = true, Firearms = true, Handgun = true, Rifle = true,
      Pistol = true, Shotgun = true, Melee = true, Blade = true,
      Sword = true, Knife = true, WeaponModel = true, WeaponModels = true,
      LocalWeapon = true, CharacterWeapons = true, HeldTool = true,
  }

  local function NR_IsGameplayAncestor(inst)
      local p = inst
      while p and p ~= workspace do
          if (BallsFolder and p == BallsFolder) or (AliveFolder and p == AliveFolder) or (RuntimeFolder and p == RuntimeFolder) then
              return true
          end
          p = p.Parent
      end
      return false
  end

  local function NR_IsProtected(inst)
      if not inst then return false end
      if inst:IsA("Tool") then return true end
      if inst:FindFirstAncestorOfClass("Tool") then return true end
      local char = LocalPlayer.Character
      if char and (inst == char or inst:IsDescendantOf(char)) then return true end
      local cam = workspace.CurrentCamera
      if cam and (inst == cam or inst:IsDescendantOf(cam)) then return true end
      local p = inst
      while p and p ~= workspace do
          local n = p.Name
          if NR_WEAPON_NAMES[n] then return true end
          p = p.Parent
      end
      local anc = inst:FindFirstAncestorOfClass("Model")
      if anc then
          local hum = anc:FindFirstChildOfClass("Humanoid")
          if hum then return true end
      end
      return false
  end

  local function NR_IsIgnored(inst)
      local p = inst
      while p and p ~= workspace do
          if p:GetAttribute('NoRender_Ignore') then return true end
          p = p.Parent
      end
      return false
  end

  local function NR_IsMapDescendant(part)
      local p = part.Parent
      while p and p ~= workspace do
          if NR_MAP_FOLDER_NAMES[p.Name] then return true end
          p = p.Parent
      end
      return part.Anchored and not NR_IsGameplayAncestor(part)
  end

  local function NR_Get(inst, prop) return inst[prop] end
  local function NR_Put(inst, prop, value) inst[prop] = value end

  local function NR_Set(inst, prop, value)
      local get, put = NR_Get, NR_Put
      if NR_HIDDEN[prop] then get = gethiddenproperty; put = sethiddenproperty end
      if not (get and put) then return end
      local ok, cur = true, get(inst, prop)
      if not ok or cur == value then return end
      put(inst, prop, value)
      local props = NR_Store[inst]
      if not props then props = {}; NR_Store[inst] = props end
      if props[prop] == nil then props[prop] = cur end
  end

  local function NR_RestoreAll()
      for inst, props in pairs(NR_Store) do
          if NR_Pinned[inst] or inst.Parent ~= nil then
              for prop, value in pairs(props) do
                  local put = NR_HIDDEN[prop] and sethiddenproperty or NR_Put
                  if put then put(inst, prop, value) end
              end
          end
      end
      table.clear(NR_Store)
  end

  local function NR_Prune()
      for inst in pairs(NR_Store) do
          if not NR_Pinned[inst] and inst.Parent == nil then NR_Store[inst] = nil end
      end
  end

  local function NR_Off(obj) NR_Set(obj, 'Enabled', false) end
  local function NR_Hide(obj) NR_Set(obj, 'Transparency', 1) end
  local function NR_OffAndClear(obj) NR_Set(obj, 'Enabled', false); obj:Clear() end

  local NR_HANDLERS = {
      ParticleEmitter = function(obj) NR_Set(obj,'Lifetime',NR_ZERO_LIFETIME); NR_OffAndClear(obj) end,
      Trail=NR_OffAndClear, Beam=NR_Off, Smoke=NR_Off, Fire=NR_Off, Sparkles=NR_Off, Highlight=NR_Off, Clouds=NR_Off,
      PointLight=NR_Off, SpotLight=NR_Off, SurfaceLight=NR_Off, BloomEffect=NR_Off, BlurEffect=NR_Off, ColorCorrectionEffect=NR_Off,
      DepthOfFieldEffect=NR_Off, SunRaysEffect=NR_Off, ColorGradingEffect=NR_Off, Decal=NR_Hide, Texture=NR_Hide,
      Explosion=function(obj) NR_Set(obj,'Visible',false) end,
      Atmosphere=function(obj) NR_Set(obj,'Density',0); NR_Set(obj,'Haze',0); NR_Set(obj,'Glare',0) end,
      Sky=function(obj) NR_Set(obj,'CelestialBodiesShown',false); NR_Set(obj,'StarCount',0) end,
  }

  local function NR_Apply(obj)
      if NR_IsIgnored(obj) or NR_IsProtected(obj) then return end
      local handler = NR_HANDLERS[obj.ClassName]
      if handler and not NR_IsGameplayAncestor(obj) then handler(obj) end
  end

  local function NR_ApplyLighting(prop)
      NR_Set(Lighting, prop, NR_LIGHTING[prop])
      local ok, now = true, NR_Get(Lighting, prop)
      if ok then NR_LightingSeen[prop] = now end
  end

  local function NR_OptimizeWorld()
      for prop in pairs(NR_LIGHTING) do NR_ApplyLighting(prop) end
      for _, c in ipairs(Lighting:GetChildren()) do NR_Apply(c) end
      NR_Set(NR_Terrain,'Decoration',false); NR_Set(NR_Terrain,'WaterWaveSize',0); NR_Set(NR_Terrain,'WaterWaveSpeed',0)
      NR_Set(NR_Terrain,'WaterReflectance',0); NR_Set(NR_Terrain,'WaterTransparency',1)
      if NR_Render then NR_Set(NR_Render,'QualityLevel',Enum.QualityLevel.Level01) end
  end

  local function NR_OnLightingChanged(prop)
      if NR_LIGHTING[prop] == nil then return end
      local ok, now = true, NR_Get(Lighting, prop)
      if not ok or now == NR_LightingSeen[prop] then return end
      local props = NR_Store[Lighting]
      if props then props[prop] = now end
      NR_ApplyLighting(prop)
  end

  local function NR_HideMapPart(part)
      if not part:IsA('BasePart') or NR_IsGameplayAncestor(part) or NR_IsProtected(part) then return end
      if part.Name == 'FLOOR' or part.Name == 'INVISIBLE_FLOOR' then return end
      if NR_HiddenParts[part] ~= nil then return end
      if part.Parent == workspace and NR_DIRECT_WORKSPACE_PARTS[part.Name] then
          NR_HiddenParts[part] = part.Transparency; part.Transparency = 1; return
      end
      if not NR_IsMapDescendant(part) then return end
      NR_HiddenParts[part] = part.Transparency; part.Transparency = 1
  end

  local function NR_RestoreMapParts()
      for part, t in pairs(NR_HiddenParts) do
          if part and part.Parent then part.Transparency = t end
      end
      table.clear(NR_HiddenParts)
  end

  local function NR_HideMapGui(obj)
      if not (obj:IsA('BillboardGui') or obj:IsA('SurfaceGui') or obj:IsA('SelectionBox')) then return end
      if NR_IsGameplayAncestor(obj) or NR_IsIgnored(obj) or NR_IsProtected(obj) then return end
      if NR_HiddenGuis2[obj] ~= nil then return end
      NR_HiddenGuis2[obj] = obj.Enabled; obj.Enabled = false
  end

  local function NR_RestoreMapGuis()
      for obj, enabled in pairs(NR_HiddenGuis2) do
          if obj and obj.Parent then obj.Enabled = enabled end
      end
      table.clear(NR_HiddenGuis2)
  end

  local function NR_HideLobbyGuis()
      local PlayerGui = LocalPlayer:FindFirstChild('PlayerGui')
      if not PlayerGui then return end
      for _, gui in ipairs(PlayerGui:GetChildren()) do
          if NR_LOBBY_GUI_NAMES[gui.Name] and gui:IsA('ScreenGui') and gui.Enabled then
              NR_HiddenGuis[gui] = true; gui.Enabled = false
          end
      end
  end

  local function NR_RestoreLobbyGuis()
      for gui in pairs(NR_HiddenGuis) do
          if gui and gui.Parent then gui.Enabled = true end
      end
      table.clear(NR_HiddenGuis)
  end

  local function NR_ProcessObj(v)
      if NR_IsIgnored(v) or NR_IsProtected(v) then return end
      NR_Apply(v); NR_HideMapPart(v); NR_HideMapGui(v)
  end

  local function NR_Enable()
      if NR_Enabled then return end
      NR_Enabled = true
      NR_Gen += 1
      local gen = NR_Gen
      local NR_DescQueue, NR_DescIdx = {}, 0
      NR_OptimizeWorld()
      NR_HideLobbyGuis()

      local Map = workspace:FindFirstChild('Map')
      if Map then
          Connections_Manager['NR_MapChanged'] = Map.ChildAdded:Connect(function(child)
              if not NR_Enabled then return end
              if child:IsA('Model') then task.defer(NR_OptimizeWorld) end
          end)
          Connections_Manager['NR_MapRemoved'] = Map.ChildRemoved:Connect(function(child)
              if not NR_Enabled then return end
              if child:IsA('Model') then task.defer(NR_RestoreMapParts) end
          end)
      end

      Connections_Manager['NR_GuiAdded'] = LocalPlayer.PlayerGui.ChildAdded:Connect(function(gui)
          if not NR_Enabled then return end
          if NR_LOBBY_GUI_NAMES[gui.Name] and gui:IsA('ScreenGui') and gui.Enabled then
              NR_HiddenGuis[gui] = true; gui.Enabled = false
          end
      end)
      Connections_Manager['NR_Descendant'] = workspace.DescendantAdded:Connect(function(v)
          NR_DescQueue[#NR_DescQueue + 1] = v
      end)
      Connections_Manager['NR_DescDrain'] = RunService.Heartbeat:Connect(function()
          if NR_DescIdx >= #NR_DescQueue then
              if #NR_DescQueue > 0 then table.clear(NR_DescQueue); NR_DescIdx = 0 end
              return
          end
          local deadline = os.clock() + 0.003
          while NR_DescIdx < #NR_DescQueue and os.clock() < deadline do
              NR_DescIdx += 1
              local v = NR_DescQueue[NR_DescIdx]
              if v and v.Parent then pcall(NR_ProcessObj, v) end
          end
          if NR_DescIdx >= #NR_DescQueue then table.clear(NR_DescQueue); NR_DescIdx = 0 end
      end)
      Connections_Manager['NR_LightingChild'] = Lighting.ChildAdded:Connect(NR_Apply)
      Connections_Manager['NR_LightingProp'] = Lighting.Changed:Connect(NR_OnLightingChanged)

      task.spawn(function()
          local list = workspace:GetDescendants()
          local deadline = os.clock() + 0.004
          for i = 1, #list do
              if NR_Gen ~= gen then return end
              NR_ProcessObj(list[i])
              if i % 64 == 0 and os.clock() > deadline then task.wait(); deadline = os.clock() + 0.004 end
          end
          list = nil
          while NR_Gen == gen do task.wait(10); NR_Prune() end
      end)
  end

  local function NR_Disable()
      if not NR_Enabled then return end
      NR_Enabled = false; NR_Gen += 1
      for _, key in ipairs(NR_CONNECTIONS) do
          local conn = Connections_Manager[key]
          if conn then conn:Disconnect(); Connections_Manager[key] = nil end
      end
      NR_RestoreAll(); NR_RestoreLobbyGuis(); NR_RestoreMapParts(); NR_RestoreMapGuis()
      table.clear(NR_LightingSeen)
  end

  local WatermarkGui = nil
  local function CreateWatermark()
      if WatermarkGui then return WatermarkGui end
      local g = Instance.new('ScreenGui')
      g.Name = 'ByteWatermark'; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 999
      g.Parent = (typeof(gethui) == 'function' and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
      g.Enabled = true

      local frame = Instance.new('Frame')
      frame.Size = UDim2.fromOffset(0, 32); frame.AutomaticSize = Enum.AutomaticSize.X
      frame.Position = UDim2.new(0.5, 0, 0, 10); frame.AnchorPoint = Vector2.new(0.5, 0)
      frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20); frame.BackgroundTransparency = 0.1; frame.BorderSizePixel = 0; frame.Parent = g

      local layout = Instance.new('UIListLayout')
      layout.FillDirection = Enum.FillDirection.Horizontal; layout.SortOrder = Enum.SortOrder.LayoutOrder
      layout.VerticalAlignment = Enum.VerticalAlignment.Center; layout.Padding = UDim.new(0, 8); layout.Parent = frame

      local padding = Instance.new('UIPadding')
      padding.PaddingLeft = UDim.new(0, 10); padding.PaddingRight = UDim.new(0, 14); padding.Parent = frame
      Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 6)

      local stroke = Instance.new('UIStroke')
      stroke.Color = Color3.fromRGB(50, 50, 50); stroke.Thickness = 1; stroke.Parent = frame

      local name = Instance.new('TextLabel')
      name.Size = UDim2.fromOffset(0, 32); name.AutomaticSize = Enum.AutomaticSize.X; name.BackgroundTransparency = 1
      name.Text = 'Byte'; name.TextColor3 = Color3.new(1, 1, 1); name.TextSize = 14; name.Font = Enum.Font.GothamBold
      name.TextXAlignment = Enum.TextXAlignment.Left; name.LayoutOrder = 2; name.Parent = frame

      local info = Instance.new('TextLabel')
      info.Size = UDim2.fromOffset(0, 32); info.AutomaticSize = Enum.AutomaticSize.X; info.BackgroundTransparency = 1
      info.TextColor3 = Color3.fromRGB(220, 220, 220); info.TextSize = 13; info.Font = Enum.Font.Gotham
      info.TextXAlignment = Enum.TextXAlignment.Left; info.LayoutOrder = 3; info.Parent = frame

      local frames, lastUpdate = 0, tick()
      local cachedRegion = "Loading..."

      task.spawn(function()
          local function FindServerText()
              local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
              if playerGui then
                  for _, desc in ipairs(playerGui:GetDescendants()) do
                      if desc:IsA("TextLabel") and desc.Text:find("Server Region:") then
                          return string.gsub(desc.Text, "Server Region:%s*", "")
                      end
                  end
              end
              local jid = game.JobId
              if jid and #jid > 0 then return string.upper(string.sub(jid, 1, 4)) end
              return "Unknown"
          end
          cachedRegion = FindServerText()
      end)

      Connections_Manager['Watermark_FPS'] = RunService.RenderStepped:Connect(function()
          frames = frames + 1
          local now = tick()
          if now - lastUpdate >= 1 then
              local realPing = 0
              local pingStat = Stats.Network and Stats.Network.ServerStatsItem and Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
              if pingStat then realPing = math.floor(pingStat:GetValue()) end
              info.Text = string.format("%s | %d FPS | %d MS | %s", os.date("%H:%M:%S"), math.floor(frames / (now - lastUpdate)), realPing, cachedRegion)
              frames = 0; lastUpdate = now
          end
      end)

      local dragging, dragStart, startPos
      Connections_Manager['Watermark_DragStart'] = frame.InputBegan:Connect(function(input)
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
              dragging, dragStart, startPos = true, input.Position, frame.Position
          end
      end)
      Connections_Manager['Watermark_DragMove'] = UserInputService.InputChanged:Connect(function(input)
          if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
              local delta = input.Position - dragStart
              frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
          end
      end)
      Connections_Manager['Watermark_DragEnd'] = UserInputService.InputEnded:Connect(function(input)
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
      end)

      WatermarkGui = g
      return g
  end

  local groupLeft = SettingsTab:AddLeftGroupbox("Performance", "gauge")
  
  groupLeft:AddToggle("Watermark", {
      Text = "Watermark",
      Default = true,
      Callback = function(state)
          local g = CreateWatermark()
          if g then g.Enabled = state end
      end,
  })

  groupLeft:AddToggle("NoRender", {
      Text = "No Render",
      Default = false,
      Tooltip = "Disables all effects, post-processing and lighting detail. Your character and weapons are kept visible.",
      Callback = function(state)
          if state then NR_Enable() else NR_Disable() end
      end,
  })

  local groupRight = SettingsTab:AddRightGroupbox("Server Actions", "refresh-cw")
  
  groupRight:AddButton({
    Text = "Rejoin Server",
    Callback = function()
      TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end,
  })

  groupRight:AddButton({
    Text = "Server Hop",
    Callback = function()
      Window:Notify({ Title = "Server Hop", Content = "Finding a new server...", Icon = "loader" })
      task.spawn(function()
        local success, result = pcall(function()
          return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if success and result and result.data then
          for _, server in ipairs(result.data) do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
              TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
              return
            end
          end
        end
        Window:Notify({ Title = "Server Hop", Content = "No servers found.", Icon = "x" })
      end)
    end,
  })

  groupRight:AddButton({
    Text = "Unload All",
    Callback = teardown,
  })

  CreateWatermark()
end

SaveManager:SetAutoSave(true)
SaveManager:LoadAutoloadConfig()

;(type(getgenv) == "function" and getgenv() or _G).BYTE_VERSION = "v2.3"