-- v1.0 (Kron v2 UI)
if _G._BPFillerGui and _G._BPFillerGui.Parent then
    pcall(function() _G._BPFillerGui:Destroy() end)
end
if _G._BPFillerGui then _G._BPFillerGui = nil end

local VERSION = "1.0"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS2 = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local Mouse = plr:GetMouse()
local IS_OWNER = (plr.Name == "mejustexploiting")

-- ─────────── IN-UI CONSOLE ───────────
local consoleLabel = nil
local consoleLines = {}
local MAX_CONSOLE_LINES = 300

local function uiLog(msg)
    local line = string.format("[%.2f] %s", tick() % 1000, tostring(msg))
    table.insert(consoleLines, line)
    while #consoleLines > MAX_CONSOLE_LINES do
        table.remove(consoleLines, 1)
    end
    if consoleLabel then
        pcall(function()
            consoleLabel.Text = table.concat(consoleLines, "\n")
        end)
    end
end

local _originalPrint = print
local _originalWarn = warn

local function _flattenArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        table.insert(parts, tostring((select(i, ...))))
    end
    return table.concat(parts, "\t")
end

print = function(...)
    local s = _flattenArgs(...)
    pcall(_originalPrint, s)
    uiLog(s)
end

warn = function(...)
    local s = "WARN: " .. _flattenArgs(...)
    pcall(_originalWarn, s)
    uiLog(s)
end

-- ─────────── REMOTE ───────────
local Interaction = RS2:WaitForChild("Interaction", 10)
local ClientIsDragging = nil
if Interaction then
    ClientIsDragging = Interaction:FindFirstChild("ClientIsDragging")
    if not ClientIsDragging then
        ClientIsDragging = Interaction:WaitForChild("ClientIsDragging", 10)
    end
end

-- ─────────── SETTINGS PERSISTENCE ───────────
local SETTINGS_FILE = "bpfiller_settings.json"

local function trySaveSettings(data)
    if not writefile then return false, "writefile unavailable" end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false, "encode failed" end
    local ok2, err = pcall(writefile, SETTINGS_FILE, encoded)
    if not ok2 then return false, tostring(err) end
    return true
end

local function tryLoadSettings()
    if not readfile or not isfile then return nil end
    local ok, exists = pcall(isfile, SETTINGS_FILE)
    if not ok or not exists then return nil end
    local ok2, contents = pcall(readfile, SETTINGS_FILE)
    if not ok2 then return nil end
    local ok3, data = pcall(function() return HttpService:JSONDecode(contents) end)
    if not ok3 then return nil end
    return data
end

local savedSettings = tryLoadSettings() or {}

-- ─────────── STATE ───────────
local fillDelay         = savedSettings.fillDelay or 0.15
local filterMinY        = savedSettings.filterMinY or 0
local filterMaxY        = savedSettings.filterMaxY or 1000
local selectedTreeClass = savedSettings.selectedTreeClass
local selectedPlayer    = plr
local selectedWoodOwner = plr
local selectedBaseOwner = savedSettings.selectedBaseOwner

local fillMethod        = savedSettings.fillMethod or "Testing/WIP"
local fillMethodLabels  = { "Working (teleport)", "Testing/WIP (hold)" }

local heldPlanks         = {}
local HOLD_FIRE_INTERVAL = savedSettings.holdFireInterval or 0.5
local fireEveryFrame     = savedSettings.fireEveryFrame or false
local fireOnceOnly       = savedSettings.fireOnceOnly or false
local fireSignature      = savedSettings.fireSignature or 1

local function resolvePlayer(name)
    if not name or name == "" or name == "(Me)" then return plr end
    return Players:FindFirstChild(name) or plr
end
if savedSettings.selectedPlayerName then
    selectedPlayer = resolvePlayer(savedSettings.selectedPlayerName)
end
if savedSettings.selectedWoodOwnerName then
    selectedWoodOwner = resolvePlayer(savedSettings.selectedWoodOwnerName)
end

local LT2_WOOD_PRESETS = {
    "Oak", "Elm", "Birch", "Cherry", "Fir", "Walnut", "Koa", "Pine",
    "Palm", "Bamboo", "Cactus", "Gold Wood", "Lava Wood", "Zombie Wood",
    "Spooky Wood", "Sinister Wood", "Cavecrawler Wood"
}

local autoFillRunning   = false
local autoFillCancel    = false
local loopMode          = false
local loopRunning       = false
local clickMode         = false
local clickConn         = nil
local nearestMode       = false
local loopStallCooldown = 0

local SCAN_INTERVAL     = 2
local lastScanAccum     = 0

-- ─────────── FLY SYSTEM ───────────
local flying = false
local flySpeed = 55
local flyBV = nil
local flyBG = nil
local flyUpBtn = nil
local flyDownBtn = nil

local function stopFly()
    flying = false
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
    if flyUpBtn then flyUpBtn.Visible = false end
    if flyDownBtn then flyDownBtn.Visible = false end
end

local function startFly()
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    flying = true

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hrp

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBG.P = 10000
    flyBG.D = 200
    flyBG.CFrame = hrp.CFrame
    flyBG.Parent = hrp

    if flyUpBtn then flyUpBtn.Visible = true end
    if flyDownBtn then flyDownBtn.Visible = true end

    task.spawn(function()
        while flying and char.Parent and hrp.Parent do
            local cam = workspace.CurrentCamera
            local dir = Vector3.zero

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.MoveDirection.Magnitude > 0 then
                dir = humanoid.MoveDirection
            end

            if UIS:IsKeyDown(Enum.KeyCode.Space) then
                dir = dir + Vector3.new(0, 1, 0)
            end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
                dir = dir + Vector3.new(0, -1, 0)
            end

            if flyUpBtn and flyUpBtn:GetAttribute("Pressed") then
                dir = dir + Vector3.new(0, 1, 0)
            end
            if flyDownBtn and flyDownBtn:GetAttribute("Pressed") then
                dir = dir + Vector3.new(0, -1, 0)
            end

            if dir.Magnitude > 0 then
                flyBV.Velocity = dir.Unit * flySpeed
            else
                flyBV.Velocity = Vector3.zero
            end

            if cam then
                flyBG.CFrame = CFrame.new(hrp.Position, hrp.Position + cam.CFrame.LookVector)
            end

            RunService.RenderStepped:Wait()
        end
        if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
        if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
    end)
end

-- ─────────── HELPERS ───────────
local function getPlayerModels()
    return workspace:FindFirstChild("PlayerModels")
end

local function ownerMatches(model, who)
    if not model or not who then return false end
    local owner = model:FindFirstChild("Owner")
    if not owner then return false end
    local ok, val = pcall(function() return owner.Value end)
    if not ok or val == nil then return false end

    if typeof(val) == "Instance" then
        if val == who then return true end
        local name, uid
        pcall(function() name = val.Name end)
        pcall(function() uid = val.UserId end)
        if name and (name == who.Name or name == who.DisplayName) then return true end
        if uid and uid == who.UserId then return true end
        return false
    end

    local s = tostring(val)
    if s == who.Name or s == who.DisplayName then return true end
    if s == tostring(who.UserId) then return true end
    if s:lower() == who.Name:lower() then return true end
    if s:lower() == who.DisplayName:lower() then return true end
    return false
end

local function isLoosePlank(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name ~= "Plank" then return false end
    if not model:FindFirstChild("TreeClass") then return false end
    if not model:FindFirstChildWhichIsA("BasePart") then return false end
    if not ownerMatches(model, selectedWoodOwner) then return false end
    return true
end

local function plankPart(model)
    if not model then return nil end
    return model:FindFirstChild("WoodSection")
        or model:FindFirstChild("Main")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function plankTreeClass(model)
    local tc = model and model:FindFirstChild("TreeClass")
    if tc and tc:IsA("StringValue") then return tc.Value end
    return nil
end

local function plankSizeY(model)
    local p = plankPart(model)
    return p and p.Size.Y or nil
end

local function isBlueprint(model)
    if not model or not model:IsA("Model") then return false end
    if not ownerMatches(model, selectedPlayer) then return false end
    local t = model:FindFirstChild("Type")
    return t and t:IsA("StringValue") and t.Value == "Blueprint"
end

local function blueprintCenter(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart.Position end
    local main = model:FindFirstChild("Main")
    if main and main:IsA("BasePart") then return main.Position end
    local mcf = model:FindFirstChild("MainCFrame")
    if mcf and mcf:IsA("CFrameValue") then return mcf.Value.Position end
    local sum, count = Vector3.zero, 0
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            sum += p.Position
            count += 1
        end
    end
    if count > 0 then return sum / count end
    return nil
end

-- ─────────── WORKING ───────────
local function grabOwnership(model, timeout)
    timeout = timeout or 1.0
    if not model or not model.Parent then return false end
    if not ClientIsDragging then return false end

    local lastInteracted = nil
    local ownerFolder = model:FindFirstChild("Owner")
    if ownerFolder then
        lastInteracted = ownerFolder:FindFirstChild("LastInteraction")
    end
    if not lastInteracted then
        lastInteracted = model:FindFirstChild("LastInteraction")
    end

    local startVal = nil
    if lastInteracted then
        pcall(function() startVal = lastInteracted.Value end)
    end

    local deadline = tick() + timeout
    while tick() < deadline do
        if not model.Parent then return false end
        pcall(function() ClientIsDragging:FireServer(model) end)
        if lastInteracted then
            local cur
            pcall(function() cur = lastInteracted.Value end)
            if cur ~= startVal and cur ~= nil then
                return true
            end
        end
        task.wait()
    end
    return lastInteracted == nil
end

local function teleportObjectTo(part, goalCF, root)
    if not part or not part.Parent then return false end
    local model = part:FindFirstAncestorOfClass("Model") or part.Parent

    if root then
        local flat = (root.Position - part.Position) * Vector3.new(1, 0, 1)
        if flat.Magnitude > 10 then
            root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
            task.wait(0.15)
        end
    end

    task.wait(0.05)
    local got = grabOwnership(model, 1.0)
    task.wait(0.05)

    if part and part.Parent then
        part.CFrame = goalCF
    end
    task.wait(0.1)
    return got
end

local function fillOneBlueprint(bp, plankEntry, root)
    if not bp or not bp.Parent then return false, "no bp" end
    if not plankEntry or not plankEntry.part or not plankEntry.part.Parent then
        return false, "no plank"
    end
    local center = blueprintCenter(bp)
    if not center then return false, "no center" end
    local goalCF = CFrame.new(center)
    local ok = teleportObjectTo(plankEntry.part, goalCF, root)
    return ok, ok and "ok" or "ownership timeout"
end

-- ─────────── WIP/HOLD ───────────
local function fireDrag(model, goalCF)
    if not ClientIsDragging then return end
    if fireSignature == 1 then
        pcall(function() ClientIsDragging:FireServer(model) end)
    elseif fireSignature == 2 then
        pcall(function() ClientIsDragging:FireServer(model, goalCF) end)
    elseif fireSignature == 3 then
        pcall(function() ClientIsDragging:FireServer(model, goalCF, true) end)
    elseif fireSignature == 4 then
        local pos = goalCF and goalCF.Position or Vector3.zero
        pcall(function() ClientIsDragging:FireServer(model, pos) end)
    elseif fireSignature == 5 then
        local hit = Mouse.Hit
        pcall(function() ClientIsDragging:FireServer(model, hit) end)
    else
        pcall(function() ClientIsDragging:FireServer(model) end)
    end
end

local function startHold(model, part, goalCF)
    if not model or not model.Parent then return false end
    if not part or not part.Parent then return false end
    heldPlanks[model] = { part = part, goalCF = goalCF, lastFire = 0 }
    return true
end

local function stopAllHolds()
    heldPlanks = {}
end

local function holdCount()
    local n = 0
    for _ in pairs(heldPlanks) do n += 1 end
    return n
end

local function quickGrab(model, timeout)
    timeout = timeout or 1.0
    if not model or not model.Parent then return false end
    if not ClientIsDragging then return false end

    local lastInteracted = nil
    local ownerFolder = model:FindFirstChild("Owner")
    if ownerFolder then
        lastInteracted = ownerFolder:FindFirstChild("LastInteraction")
    end
    if not lastInteracted then
        lastInteracted = model:FindFirstChild("LastInteraction")
    end

    local startVal = nil
    if lastInteracted then
        pcall(function() startVal = lastInteracted.Value end)
    end

    local deadline = tick() + timeout
    while tick() < deadline do
        if not model.Parent then return false end
        pcall(function() ClientIsDragging:FireServer(model) end)
        if lastInteracted then
            local cur
            pcall(function() cur = lastInteracted.Value end)
            if cur ~= startVal and cur ~= nil then
                return true
            end
        end
        task.wait()
    end
    return lastInteracted == nil
end

local function movePlayerNear(root, targetPart)
    if not root or not targetPart then return end
    local flat = (root.Position - targetPart.Position) * Vector3.new(1, 0, 1)
    if flat.Magnitude > 10 then
        root.CFrame = CFrame.new(targetPart.Position + Vector3.new(0, 3, 0))
        task.wait(0.15)
    end
end

local function holdInBlueprint(bp, plankEntry, root)
    if not bp or not bp.Parent then return false, "no bp" end
    if not plankEntry or not plankEntry.part or not plankEntry.part.Parent then
        return false, "no plank"
    end

    if heldPlanks[plankEntry.model] then
        local center = blueprintCenter(bp)
        if center then
            local cf = CFrame.new(center)
            heldPlanks[plankEntry.model].goalCF = cf
            fireDrag(plankEntry.model, cf)
        end
        return true, "re-targeted"
    end

    local center = blueprintCenter(bp)
    if not center then return false, "no center" end
    local goalCF = CFrame.new(center)

    movePlayerNear(root, plankEntry.part)
    local got = quickGrab(plankEntry.model, 1.0)
    if not got then return false, "grab failed" end

    if plankEntry.part and plankEntry.part.Parent then
        plankEntry.part.CFrame = goalCF
    end

    startHold(plankEntry.model, plankEntry.part, goalCF)
    fireDrag(plankEntry.model, goalCF)
    return true, "held"
end

-- ─────────── SCANNING ───────────
local function scanPlanks()
    local pm = getPlayerModels()
    local byTree = {}
    local total = 0
    if not pm then return byTree, total end
    for _, m in ipairs(pm:GetChildren()) do
        if isLoosePlank(m) and not heldPlanks[m] then
            local tc = plankTreeClass(m) or "?"
            local y = plankSizeY(m) or 0
            byTree[tc] = byTree[tc] or { count = 0, sizes = {} }
            byTree[tc].count += 1
            local key = string.format("%.2f", y)
            byTree[tc].sizes[key] = (byTree[tc].sizes[key] or 0) + 1
            total += 1
        end
    end
    return byTree, total
end

local function collectMatchingPlanks()
    local pm = getPlayerModels()
    local list = {}
    if not pm then return list end
    for _, m in ipairs(pm:GetChildren()) do
        if isLoosePlank(m) and not heldPlanks[m] then
            local tc = plankTreeClass(m)
            local y = plankSizeY(m)
            if tc and y then
                local treeOK = (not selectedTreeClass) or (tc == selectedTreeClass)
                local sizeOK = (y >= filterMinY and y <= filterMaxY)
                if treeOK and sizeOK then
                    local p = plankPart(m)
                    if p then
                        table.insert(list, { model = m, part = p, treeClass = tc, sizeY = y })
                    end
                end
            end
        end
    end
    return list
end

local function collectBlueprints()
    local pm = getPlayerModels()
    local list = {}
    if not pm then return list end
    for _, m in ipairs(pm:GetChildren()) do
        if isBlueprint(m) then
            table.insert(list, m)
        end
    end
    return list
end

-- ─────────── BASE HELPERS ───────────
local function getBaseOwnerOptions()
    local pm = getPlayerModels()
    local seen = {}
    local opts = {}
    if pm then
        for _, m in ipairs(pm:GetChildren()) do
            if m:IsA("Model") then
                local owner = m:FindFirstChild("Owner")
                if owner then
                    local ok, v = pcall(function() return owner.Value end)
                    if ok and v ~= nil then
                        local name = typeof(v) == "Instance" and v.Name or tostring(v)
                        if name and name ~= "" and not seen[name] then
                            seen[name] = true
                            table.insert(opts, name)
                        end
                    end
                end
            end
        end
    end
    table.sort(opts, function(a, b) return a:lower() < b:lower() end)
    return opts
end

local function getBasePosition(playerName)
    local pm = getPlayerModels()
    if not pm or not playerName then return nil end
    local positions = {}
    for _, m in ipairs(pm:GetChildren()) do
        if m:IsA("Model") then
            local owner = m:FindFirstChild("Owner")
            if owner then
                local ok, v = pcall(function() return owner.Value end)
                if ok and v ~= nil then
                    local name = typeof(v) == "Instance" and v.Name or tostring(v)
                    if name == playerName then
                        local t = m:FindFirstChild("Type")
                        local typeVal = t and t:IsA("StringValue") and t.Value or ""
                        if typeVal == "Blueprint" or typeVal == "Base" or typeVal == "Plot" then
                            local c = blueprintCenter(m)
                            if c then table.insert(positions, c) end
                        end
                    end
                end
            end
        end
    end
    if #positions == 0 then return nil end
    local sum = Vector3.zero
    for _, p in ipairs(positions) do sum += p end
    return sum / #positions
end

local _setStatusRef = nil

local function tpToClosestBP()
    local char = plr.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        if _setStatusRef then _setStatusRef("No character") end
        return
    end
    local bps = collectBlueprints()
    if #bps == 0 then
        if _setStatusRef then _setStatusRef("No blueprints") end
        return
    end
    local nearest, nearestDist = nil, math.huge
    for _, bp in ipairs(bps) do
        local c = blueprintCenter(bp)
        if c then
            local d = (c - root.Position).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = c
            end
        end
    end
    if not nearest then
        if _setStatusRef then _setStatusRef("No blueprint center") end
        return
    end
    root.CFrame = CFrame.new(nearest + Vector3.new(0, 5, 0))
    if _setStatusRef then
        _setStatusRef(string.format("TP'd to closest BP (%.0f studs)", nearestDist))
    end
end

local function tpToBase()
    local name = selectedBaseOwner
    if not name or name == "" then
        if _setStatusRef then _setStatusRef("Pick a base first") end
        return
    end
    local pos = getBasePosition(name)
    if not pos then
        if _setStatusRef then _setStatusRef("No base found for " .. name) end
        return
    end
    local char = plr.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        if _setStatusRef then _setStatusRef("No character") end
        return
    end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
    if _setStatusRef then _setStatusRef("TP'd to " .. name .. "'s base") end
end

-- ─────────── UI: KRON V2 LAYOUT ───────────
local gui = Instance.new("ScreenGui")
gui.Name = "BPFillerStandalone"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.IgnoreGuiInset = false
gui.Parent = plr:WaitForChild("PlayerGui")
_G._BPFillerGui = gui

local ACCENT = Color3.fromRGB(120, 80, 255)
local ACCENT_SOFT = Color3.fromRGB(80, 55, 180)
local BG_DARK = Color3.fromRGB(13, 13, 17)
local BG_SIDEBAR = Color3.fromRGB(18, 18, 24)
local BG_ROW = Color3.fromRGB(26, 26, 33)
local BG_ROW_HOVER = Color3.fromRGB(34, 34, 44)
local TEXT_WHITE = Color3.fromRGB(240, 240, 245)
local TEXT_GRAY = Color3.fromRGB(150, 150, 165)
local TEXT_DIM = Color3.fromRGB(100, 100, 115)
local WARN_RED = Color3.fromRGB(230, 120, 120)

-- Floating toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleBtn"
toggleBtn.Size = UDim2.fromOffset(40, 40)
toggleBtn.Position = UDim2.new(1, -55, 0, 15)
toggleBtn.BackgroundColor3 = BG_DARK
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "K"
toggleBtn.TextColor3 = TEXT_WHITE
toggleBtn.TextSize = 18
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.ZIndex = 100
toggleBtn.Parent = gui
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 20)
local toggleStroke = Instance.new("UIStroke", toggleBtn)
toggleStroke.Color = ACCENT
toggleStroke.Thickness = 2

-- Fly buttons
flyUpBtn = Instance.new("TextButton")
flyUpBtn.Size = UDim2.fromOffset(50, 50)
flyUpBtn.Position = UDim2.new(1, -70, 1, -130)
flyUpBtn.BackgroundColor3 = BG_DARK
flyUpBtn.BorderSizePixel = 0
flyUpBtn.Text = "▲"
flyUpBtn.TextColor3 = TEXT_WHITE
flyUpBtn.TextSize = 18
flyUpBtn.Font = Enum.Font.GothamBold
flyUpBtn.ZIndex = 100
flyUpBtn.Visible = false
flyUpBtn.Parent = gui
Instance.new("UICorner", flyUpBtn).CornerRadius = UDim.new(0, 25)
Instance.new("UIStroke", flyUpBtn).Color = ACCENT

flyDownBtn = Instance.new("TextButton")
flyDownBtn.Size = UDim2.fromOffset(50, 50)
flyDownBtn.Position = UDim2.new(1, -70, 1, -75)
flyDownBtn.BackgroundColor3 = BG_DARK
flyDownBtn.BorderSizePixel = 0
flyDownBtn.Text = "▼"
flyDownBtn.TextColor3 = TEXT_WHITE
flyDownBtn.TextSize = 18
flyDownBtn.Font = Enum.Font.GothamBold
flyDownBtn.ZIndex = 100
flyDownBtn.Visible = false
flyDownBtn.Parent = gui
Instance.new("UICorner", flyDownBtn).CornerRadius = UDim.new(0, 25)
Instance.new("UIStroke", flyDownBtn).Color = ACCENT

for _, btn in ipairs({flyUpBtn, flyDownBtn}) do
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            btn:SetAttribute("Pressed", true)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            btn:SetAttribute("Pressed", false)
        end
    end)
end

-- Main panel
local panelW, panelH = 360, 600
local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UDim2.fromOffset(panelW, panelH)
panel.Position = UDim2.new(0.5, -panelW / 2, 0.5, -panelH / 2)
panel.BackgroundColor3 = BG_DARK
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = false
panel.ClipsDescendants = true
panel.Visible = true
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Color = ACCENT_SOFT
pStroke.Thickness = 1.5

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -100, 1, 0)
titleLbl.Position = UDim2.fromOffset(14, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Blueprint Filler"
titleLbl.TextColor3 = TEXT_WHITE
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = titleBar

local versionLbl = Instance.new("TextLabel")
versionLbl.Size = UDim2.new(0, 40, 1, 0)
versionLbl.Position = UDim2.new(0, 130, 0, 0)
versionLbl.BackgroundTransparency = 1
versionLbl.Text = "v" .. VERSION
versionLbl.TextColor3 = TEXT_DIM
versionLbl.Font = Enum.Font.Gotham
versionLbl.TextSize = 10
versionLbl.TextXAlignment = Enum.TextXAlignment.Left
versionLbl.Parent = titleBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.fromOffset(24, 24)
minimizeBtn.Position = UDim2.new(1, -60, 0, 6)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "—"
minimizeBtn.TextColor3 = TEXT_WHITE
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 14
minimizeBtn.Parent = titleBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 5)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(24, 24)
closeBtn.Position = UDim2.new(1, -32, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = TEXT_WHITE
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

-- Sidebar
local SIDEBAR_W = 46
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -36)
sidebar.Position = UDim2.fromOffset(0, 36)
sidebar.BackgroundColor3 = BG_SIDEBAR
sidebar.BorderSizePixel = 0
sidebar.Parent = panel

local sidebarLayout = Instance.new("UIListLayout", sidebar)
sidebarLayout.Padding = UDim.new(0, 2)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
local sidebarPad = Instance.new("UIPadding", sidebar)
sidebarPad.PaddingTop = UDim.new(0, 8)

-- Sidebar bottom-right corner fix
local sidebarFix = Instance.new("Frame")
sidebarFix.Size = UDim2.new(0, SIDEBAR_W, 0, 10)
sidebarFix.Position = UDim2.new(0, 0, 1, -10)
sidebarFix.BackgroundColor3 = BG_SIDEBAR
sidebarFix.BorderSizePixel = 0
sidebarFix.ZIndex = 0
sidebarFix.Parent = panel

-- Content container
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -SIDEBAR_W, 1, -36)
content.Position = UDim2.fromOffset(SIDEBAR_W, 36)
content.BackgroundColor3 = BG_DARK
content.BorderSizePixel = 0
content.Parent = panel

-- Body (scrollable)
local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -20, 1, -8)
body.Position = UDim2.fromOffset(8, 4)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = ACCENT
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = content

local layout = Instance.new("UIListLayout", body)
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local bodyPad = Instance.new("UIPadding", body)
bodyPad.PaddingTop = UDim.new(0, 6)
bodyPad.PaddingBottom = UDim.new(0, 12)

-- Resize handle
local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.fromOffset(16, 16)
resizeHandle.Position = UDim2.new(1, -20, 1, -20)
resizeHandle.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
resizeHandle.BorderSizePixel = 0
resizeHandle.Text = ""
resizeHandle.AutoButtonColor = false
resizeHandle.ZIndex = 60
resizeHandle.Parent = panel
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 4)
for i = 1, 3 do
    local line = Instance.new("Frame")
    line.Size = UDim2.fromOffset(8 - i * 2, 1)
    line.Position = UDim2.fromOffset(3, 4 + i * 3)
    line.BackgroundColor3 = TEXT_GRAY
    line.BorderSizePixel = 0
    line.Parent = resizeHandle
end

-- Side grip
local sideGrip = Instance.new("TextButton")
sideGrip.Name = "SideGrip"
sideGrip.Size = UDim2.new(0, 10, 1, -46)
sideGrip.Position = UDim2.new(1, -12, 0, 42)
sideGrip.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
sideGrip.BorderSizePixel = 0
sideGrip.Text = ""
sideGrip.AutoButtonColor = false
sideGrip.ZIndex = 55
sideGrip.Parent = panel
Instance.new("UICorner", sideGrip).CornerRadius = UDim.new(0, 4)

-- Drag handle for title bar
local function makeDragHandle(frame)
    local dragging = false
    local dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

makeDragHandle(titleBar)
makeDragHandle(sideGrip)

-- ─────────── TAB SYSTEM ───────────
local sectionMarkers = {}
local tabButtons = {}
local tabIndicators = {}
local activeTab = nil

local TAB_DEFS = {
    { key = "target", icon = "◎", label = "Target", order = 1 },
    { key = "planks", icon = "❖", label = "Planks", order = 2 },
    { key = "fill",   icon = "▶", label = "Fill",   order = 3 },
    { key = "nav",    icon = "✦", label = "Nav",    order = 4 },
    { key = "config", icon = "⚙", label = "Config", order = 5 },
    { key = "log",    icon = "☰", label = "Log",    order = 6 },
}
if IS_OWNER then
    table.insert(TAB_DEFS, { key = "debug", icon = "⚒", label = "Debug", order = 7 })
end

local function setActiveTab(key, silent)
    activeTab = key
    for k, btn in pairs(tabButtons) do
        local ind = tabIndicators[k]
        if k == key then
            btn.TextColor3 = TEXT_WHITE
            btn.BackgroundTransparency = 0
            btn.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
            if ind then ind.Visible = true end
        else
            btn.TextColor3 = TEXT_DIM
            btn.BackgroundTransparency = 1
            if ind then ind.Visible = false end
        end
    end
end

local function scrollToTab(key)
    local marker = sectionMarkers[key]
    if not marker then return end
    local bodyTopAbsY = body.AbsolutePosition.Y
    local markerAbsY = marker.AbsolutePosition.Y
    local currentScroll = body.CanvasPosition.Y
    local targetY = currentScroll + (markerAbsY - bodyTopAbsY) - 8
    targetY = math.max(0, targetY)

    local canvasH = body.AbsoluteCanvasSize.Y
    local frameH = body.AbsoluteSize.Y
    local maxY = math.max(0, canvasH - frameH)
    targetY = math.min(targetY, maxY)

    local tween = TweenService:Create(body,
        TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { CanvasPosition = Vector2.new(0, targetY) })
    tween:Play()
    setActiveTab(key)
end

local function makeTabButton(def)
    local btn = Instance.new("TextButton")
    btn.Name = "Tab_" .. def.key
    btn.Size = UDim2.new(1, -8, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
    btn.BackgroundTransparency = 1
    btn.BorderSizePixel = 0
    btn.Text = def.icon
    btn.TextColor3 = TEXT_DIM
    btn.TextSize = 18
    btn.Font = Enum.Font.GothamBold
    btn.LayoutOrder = def.order
    btn.AutoButtonColor = false
    btn.Parent = sidebar

    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local ind = Instance.new("Frame")
    ind.Size = UDim2.new(0, 3, 0, 20)
    ind.Position = UDim2.new(0, -1, 0.5, -10)
    ind.BackgroundColor3 = ACCENT
    ind.BorderSizePixel = 0
    ind.Visible = false
    ind.Parent = btn
    Instance.new("UICorner", ind).CornerRadius = UDim.new(0, 2)

    btn.MouseEnter:Connect(function()
        if activeTab ~= def.key then
            btn.BackgroundTransparency = 0.5
        end
    end)
    btn.MouseLeave:Connect(function()
        if activeTab ~= def.key then
            btn.BackgroundTransparency = 1
        end
    end)
    btn.MouseButton1Click:Connect(function()
        scrollToTab(def.key)
    end)

    tabButtons[def.key] = btn
    tabIndicators[def.key] = ind
end

-- ─────────── UI FACTORY ───────────
local ROW_SECTION  = 22
local ROW_PARA     = 42
local ROW_BTN      = 36
local ROW_BTN_DESC = 50
local ROW_TOGGLE   = 38
local ROW_TOG_DESC = 50
local ROW_INPUT    = 38
local ROW_SLIDER   = 48
local ROW_DROPDOWN = 42

local function makeSection(text, order, tabKey)
    local container = Instance.new("Frame")
    container.Name = "Section_" .. tostring(text)
    container.Size = UDim2.new(1, 0, 0, ROW_SECTION)
    container.BackgroundTransparency = 1
    container.LayoutOrder = order
    container.Parent = body

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 0, 12)
    bar.Position = UDim2.new(0, 0, 0.5, -6)
    bar.BackgroundColor3 = ACCENT
    bar.BorderSizePixel = 0
    bar.Parent = container
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -14, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = TEXT_WHITE
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    if tabKey then
        sectionMarkers[tabKey] = container
    end
    return container
end

local function makeParagraph(title, desc, order, color)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, ROW_PARA)
    frame.BackgroundColor3 = BG_ROW
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -16, 0, 14)
    t.Position = UDim2.fromOffset(8, 6)
    t.BackgroundTransparency = 1
    t.Text = title
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = frame

    local d = Instance.new("TextLabel")
    d.Size = UDim2.new(1, -16, 0, 20)
    d.Position = UDim2.fromOffset(8, 20)
    d.BackgroundTransparency = 1
    d.Text = desc
    d.TextColor3 = color or TEXT_GRAY
    d.Font = Enum.Font.Gotham
    d.TextSize = 9
    d.TextXAlignment = Enum.TextXAlignment.Left
    d.TextWrapped = true
    d.Parent = frame

    return {
        setDesc = function(_, txt) d.Text = txt end,
        setColor = function(_, c) d.TextColor3 = c end,
        frame = frame,
    }
end

local function makeButton(text, desc, onClick, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, desc and ROW_BTN_DESC or ROW_BTN)
    btn.BackgroundColor3 = BG_ROW
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = order
    btn.Parent = body
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -16, 0, 14)
    t.Position = UDim2.fromOffset(8, desc and 6 or 11)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = btn

    if desc then
        local d = Instance.new("TextLabel")
        d.Size = UDim2.new(1, -16, 0, 20)
        d.Position = UDim2.fromOffset(8, 22)
        d.BackgroundTransparency = 1
        d.Text = desc
        d.TextColor3 = TEXT_GRAY
        d.Font = Enum.Font.Gotham
        d.TextSize = 9
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.TextWrapped = true
        d.Parent = btn
    end

    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = BG_ROW_HOVER
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = BG_ROW
    end)
    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(onClick)
        if not ok then warn("[BPFiller] button error: " .. tostring(err)) end
    end)
    return btn
end

local function makeToggle(text, desc, default, onChange, order)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, desc and ROW_TOG_DESC or ROW_TOGGLE)
    frame.BackgroundColor3 = BG_ROW
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -70, 0, 14)
    t.Position = UDim2.fromOffset(8, desc and 6 or 12)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = frame

    if desc then
        local d = Instance.new("TextLabel")
        d.Size = UDim2.new(1, -70, 0, 20)
        d.Position = UDim2.fromOffset(8, 22)
        d.BackgroundTransparency = 1
        d.Text = desc
        d.TextColor3 = TEXT_GRAY
        d.Font = Enum.Font.Gotham
        d.TextSize = 9
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.TextWrapped = true
        d.Parent = frame
    end

    local state = default
    local switch = Instance.new("TextButton")
    switch.Size = UDim2.fromOffset(42, 22)
    switch.Position = UDim2.new(1, -50, 0.5, -11)
    switch.BackgroundColor3 = state and ACCENT or Color3.fromRGB(45, 45, 55)
    switch.BorderSizePixel = 0
    switch.Text = ""
    switch.AutoButtonColor = false
    switch.Parent = frame
    Instance.new("UICorner", switch).CornerRadius = UDim.new(0, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = state and UDim2.new(1, -18, 0, 3) or UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = TEXT_WHITE
    knob.BorderSizePixel = 0
    knob.Parent = switch
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 8)

    local function setState(v)
        state = v
        switch.BackgroundColor3 = state and ACCENT or Color3.fromRGB(45, 45, 55)
        knob.Position = state and UDim2.new(1, -18, 0, 3) or UDim2.fromOffset(3, 3)
    end

    switch.MouseButton1Click:Connect(function()
        setState(not state)
        local ok, err = pcall(onChange, state)
        if not ok then warn("[BPFiller] toggle error: " .. tostring(err)) end
    end)
    return { Set = function(_, v) setState(v) end }
end

local function makeInput(text, default, onChange, order)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, ROW_INPUT)
    frame.BackgroundColor3 = BG_ROW
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromOffset(90, ROW_INPUT)
    t.Position = UDim2.fromOffset(8, 0)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = frame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -112, 0, 28)
    box.Position = UDim2.new(0, 104, 0.5, -14)
    box.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    box.BorderSizePixel = 0
    box.Text = tostring(default)
    box.TextColor3 = TEXT_WHITE
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 12
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Color3.fromRGB(50, 50, 65)
    bs.Thickness = 1
    box.Focused:Connect(function() bs.Color = ACCENT end)
    box.FocusLost:Connect(function()
        bs.Color = Color3.fromRGB(50, 50, 65)
        local ok, err = pcall(onChange, box.Text)
        if not ok then warn("[BPFiller] input error: " .. tostring(err)) end
    end)
    return { Set = function(_, v) box.Text = tostring(v) end }
end

local function makeSlider(text, min, max, default, onChange, order)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, ROW_SLIDER)
    frame.BackgroundColor3 = BG_ROW
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -70, 0, 14)
    t.Position = UDim2.fromOffset(8, 6)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = frame

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.fromOffset(60, 14)
    valLbl.Position = UDim2.new(1, -68, 0, 6)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = string.format("%.3f", default)
    valLbl.TextColor3 = ACCENT
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = frame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -16, 0, 6)
    track.Position = UDim2.fromOffset(8, 30)
    track.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    track.BorderSizePixel = 0
    track.Parent = frame
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0)
    knob.BackgroundColor3 = TEXT_WHITE
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 7)

    local dragging = false
    local function setFromX(x)
        local abs = track.AbsolutePosition.X
        local size = track.AbsoluteSize.X
        if size <= 0 then return end
        local frac = math.clamp((x - abs) / size, 0, 1)
        local val = min + (max - min) * frac
        fill.Size = UDim2.new(frac, 0, 1, 0)
        knob.Position = UDim2.new(frac, 0, 0.5, 0)
        valLbl.Text = string.format("%.3f", val)
        local ok, err = pcall(onChange, val)
        if not ok then warn("[BPFiller] slider error: " .. tostring(err)) end
    end

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local openDropdowns = {}

local function closeAllDropdowns(except)
    for _, dd in ipairs(openDropdowns) do
        if dd ~= except then dd:close() end
    end
end

local function makeDropdown(text, values, default, onChange, order)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, ROW_DROPDOWN)
    frame.BackgroundColor3 = BG_ROW
    frame.BorderSizePixel = 0
    frame.LayoutOrder = order
    frame.Parent = body
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromOffset(110, ROW_DROPDOWN)
    t.Position = UDim2.fromOffset(8, 0)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = TEXT_WHITE
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = frame

    local sel = Instance.new("TextButton")
    sel.Size = UDim2.new(1, -128, 0, 28)
    sel.Position = UDim2.new(0, 118, 0.5, -14)
    sel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    sel.BorderSizePixel = 0
    sel.Text = ""
    sel.AutoButtonColor = false
    sel.TextXAlignment = Enum.TextXAlignment.Left
    sel.Parent = frame
    Instance.new("UICorner", sel).CornerRadius = UDim.new(0, 5)
    local ss = Instance.new("UIStroke", sel)
    ss.Color = Color3.fromRGB(50, 50, 65)
    ss.Thickness = 1

    local selLbl = Instance.new("TextLabel")
    selLbl.Size = UDim2.new(1, -26, 1, 0)
    selLbl.Position = UDim2.fromOffset(10, 0)
    selLbl.BackgroundTransparency = 1
    selLbl.Text = tostring(default)
    selLbl.TextColor3 = TEXT_WHITE
    selLbl.Font = Enum.Font.GothamMedium
    selLbl.TextSize = 11
    selLbl.TextXAlignment = Enum.TextXAlignment.Left
    selLbl.Parent = sel

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.fromOffset(18, 28)
    arrow.Position = UDim2.new(1, -20, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▾"
    arrow.TextColor3 = TEXT_GRAY
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 11
    arrow.Parent = sel

    local currentValues = values
    local open = false
    local listFrame = nil

    local function closeList()
        if listFrame then listFrame:Destroy(); listFrame = nil end
        open = false
    end

    local function openList()
        closeAllDropdowns()
        listFrame = Instance.new("ScrollingFrame")
        listFrame.Name = "DropdownList"
        listFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        listFrame.BorderSizePixel = 0
        listFrame.ZIndex = 1000
        listFrame.ScrollBarThickness = 4
        listFrame.ScrollBarImageColor3 = ACCENT
        listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        listFrame.ClipsDescendants = true

        local ap = sel.AbsolutePosition
        listFrame.Position = UDim2.fromOffset(ap.X, ap.Y + sel.AbsoluteSize.Y + 2)
        listFrame.Size = UDim2.fromOffset(sel.AbsoluteSize.X, math.min(#currentValues * 24 + 6, 160))

        listFrame.Parent = gui
        Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 5)
        local ls = Instance.new("UIStroke", listFrame)
        ls.Color = ACCENT_SOFT
        ls.Thickness = 1

        local lLayout = Instance.new("UIListLayout", listFrame)
        lLayout.Padding = UDim.new(0, 2)
        lLayout.SortOrder = Enum.SortOrder.LayoutOrder
        lLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

        for _, v in ipairs(currentValues) do
            local item = Instance.new("TextButton")
            item.Size = UDim2.new(1, -6, 0, 22)
            item.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
            item.BorderSizePixel = 0
            item.Text = tostring(v)
            item.TextColor3 = TEXT_WHITE
            item.Font = Enum.Font.GothamMedium
            item.TextSize = 11
            item.AutoButtonColor = false
            item.Parent = listFrame
            Instance.new("UICorner", item).CornerRadius = UDim.new(0, 4)

            item.MouseEnter:Connect(function() item.BackgroundColor3 = BG_ROW_HOVER end)
            item.MouseLeave:Connect(function() item.BackgroundColor3 = Color3.fromRGB(28, 28, 36) end)
            item.MouseButton1Click:Connect(function()
                selLbl.Text = tostring(v)
                closeList()
                local ok, err = pcall(onChange, v)
                if not ok then warn("[BPFiller] dropdown error: " .. tostring(err)) end
            end)
        end
        open = true
    end

    sel.MouseButton1Click:Connect(function()
        if open then closeList() else openList() end
    end)

    local ddHandle = {
        Set = function(_, v) selLbl.Text = tostring(v) end,
        SetValues = function(_, newValues)
            currentValues = newValues
            if open then closeList(); openList() end
        end,
        close = closeList,
        frame = frame,
    }
    table.insert(openDropdowns, ddHandle)
    return ddHandle
end

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
    and input.UserInputType ~= Enum.UserInputType.Touch then return end
    for _, dd in ipairs(openDropdowns) do dd:close() end
end)

-- ─────────── HOLD TICKER ───────────
task.spawn(function()
    while gui and gui.Parent do
        local now = tick()
        for model, data in pairs(heldPlanks) do
            if not model.Parent or not data.part.Parent then
                heldPlanks[model] = nil
            else
                if data.part.Parent then
                    data.part.CFrame = data.goalCF
                end
                if not fireOnceOnly then
                    if fireEveryFrame then
                        data.lastFire = now
                        fireDrag(model, data.goalCF)
                    elseif now - data.lastFire >= HOLD_FIRE_INTERVAL then
                        data.lastFire = now
                        fireDrag(model, data.goalCF)
                    end
                end
            end
        end
        RunService.RenderStepped:Wait()
    end
end)

-- ─────────── LOGIC ───────────
local statusPara = nil
local inventoryPara = nil
local treeLabelPara = nil
local woodTypeDropdown = nil
local playerDropdown = nil
local woodOwnerDropdown = nil
local baseDropdown = nil
local holdCountPara = nil
local crossWarnPara = nil

local function setStatus(text)
    if statusPara then pcall(function() statusPara:setDesc(statusPara, text) end) end
    print("[Status] " .. tostring(text))
end
_setStatusRef = setStatus

local function updateCrossWarn()
    if not crossWarnPara then return end
    if selectedWoodOwner == plr then
        pcall(function()
            crossWarnPara:setDesc(crossWarnPara, "Wood source: yourself (grabs will work).")
            crossWarnPara:setColor(crossWarnPara, TEXT_GRAY)
        end)
    else
        pcall(function()
            crossWarnPara:setDesc(crossWarnPara,
                "WARNING: Wood source is " .. selectedWoodOwner.Name .. " - grabs may fail without perms.")
            crossWarnPara:setColor(crossWarnPara, WARN_RED)
        end)
    end
end

local function setHoldCount()
    if holdCountPara then
        pcall(function() holdCountPara:setDesc(holdCountPara, "Currently holding: " .. holdCount() .. " planks") end)
    end
end

local function isHoldMode()
    return fillMethod == "Testing/WIP"
end

local function getPlayerOptions()
    local opts = { "(Me)" }
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr then table.insert(opts, p.Name) end
    end
    table.sort(opts, function(a, b)
        if a == "(Me)" then return true end
        if b == "(Me)" then return false end
        return a:lower() < b:lower()
    end)
    return opts
end

local function getWoodTypeOptions(discovered)
    local seen = { ["(All)"] = true }
    local opts = { "(All)" }
    for _, w in ipairs(LT2_WOOD_PRESETS) do
        if not seen[w] then seen[w] = true; table.insert(opts, w) end
    end
    if discovered then
        for tc, _ in pairs(discovered) do
            if not seen[tc] then seen[tc] = true; table.insert(opts, tc) end
        end
    end
    table.sort(opts, function(a, b)
        if a == "(All)" then return true end
        if b == "(All)" then return false end
        return a:lower() < b:lower()
    end)
    return opts
end

local function getFireSigOptions()
    return {
        "1) Model only",
        "2) Model + CFrame",
        "3) Model + CFrame + true",
        "4) Model + Vector3",
        "5) Model + Mouse.Hit",
    }
end

local function doFill(bp, plankEntry, root)
    if isHoldMode() then
        return holdInBlueprint(bp, plankEntry, root)
    else
        return fillOneBlueprint(bp, plankEntry, root)
    end
end

local function fillAllBlueprints()
    if autoFillRunning then
        autoFillCancel = true
        setStatus("Cancelling...")
        return
    end

    local pl = collectMatchingPlanks()
    if #pl == 0 then setStatus("No matching planks"); return end
    local bps = collectBlueprints()
    if #bps == 0 then setStatus("No blueprints for " .. selectedPlayer.Name); return end

    autoFillRunning = true
    autoFillCancel = false
    local tag = isHoldMode() and "HOLD" or "TP"
    setStatus(string.format("Fill [%s]: %d bps / %d planks", tag, #bps, #pl))

    task.spawn(function()
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local plankIdx = 1
        local filled, failed = 0, 0

        for i, bp in ipairs(bps) do
            if autoFillCancel then break end
            if not bp.Parent then continue end

            local plankEntry = nil
            for _ = 1, #pl do
                local e = pl[plankIdx]
                plankIdx = (plankIdx % #pl) + 1
                if e.part and e.part.Parent then
                    if isHoldMode() then
                        if not heldPlanks[e.model] then plankEntry = e; break end
                    else
                        plankEntry = e; break
                    end
                end
            end
            if not plankEntry then setStatus("Ran out of matching planks"); break end

            setStatus(string.format("%s %d/%d (%s)", tag, i, #bps, bp.Name))
            local ok = doFill(bp, plankEntry, root)
            if ok then filled += 1 else failed += 1 end
            setHoldCount()
            task.wait(fillDelay)
        end

        autoFillRunning = false
        setStatus(string.format("Done: %d filled, %d failed", filled, failed))
    end)
end

local function fillNearestBlueprint()
    local char = plr.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then setStatus("No character"); return end
    local bps = collectBlueprints()
    if #bps == 0 then setStatus("No blueprints"); return end

    local nearest, nearestDist = nil, math.huge
    for _, bp in ipairs(bps) do
        local c = blueprintCenter(bp)
        if c then
            local d = (c - root.Position).Magnitude
            if d < nearestDist then nearestDist = d; nearest = bp end
        end
    end
    if not nearest then setStatus("No blueprint with center"); return end

    local pl = collectMatchingPlanks()
    if #pl == 0 then setStatus("No matching planks"); return end

    local entry = pl[1]
    local ok = doFill(nearest, entry, root)
    setHoldCount()
    if ok then setStatus(string.format("Filled nearest: %s (%.0f studs)", nearest.Name, nearestDist))
    else setStatus("Fill nearest failed") end
end

local function loopTick()
    if loopRunning then return end
    if tick() < loopStallCooldown then return end

    if #collectMatchingPlanks() == 0 then
        setStatus("Loop: waiting for planks...")
        return
    end
    local bps = collectBlueprints()
    if #bps == 0 then return end

    loopRunning = true
    task.spawn(function()
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local pl = collectMatchingPlanks()
        local plankIdx = 1
        local filled = 0
        local tag = isHoldMode() and "HOLD" or "TP"

        for _, bp in ipairs(bps) do
            if not loopMode then break end
            if not bp.Parent then continue end
            local plankEntry = nil
            for _ = 1, #pl do
                local e = pl[plankIdx]
                plankIdx = (plankIdx % math.max(1, #pl)) + 1
                if e.part and e.part.Parent then
                    if isHoldMode() then
                        if not heldPlanks[e.model] then plankEntry = e; break end
                    else
                        plankEntry = e; break
                    end
                end
            end
            if not plankEntry then break end
            setStatus(string.format("Loop [%s]: %s", tag, bp.Name))
            if doFill(bp, plankEntry, root) then filled += 1 end
            setHoldCount()
            task.wait(fillDelay)
        end
        loopRunning = false

        if filled == 0 then
            loopStallCooldown = tick() + 5
            setStatus("Loop stalled (0 filled) - paused 5s")
        else
            setStatus(string.format("Loop pass: %d filled", filled))
        end
    end)
end

local clickToggleHandle = nil

local function stopClickMode()
    clickMode = false
    if clickConn then clickConn:Disconnect(); clickConn = nil end
    if clickToggleHandle then pcall(function() clickToggleHandle:Set(false) end) end
end

local function startClickMode()
    clickMode = true
    clickConn = UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not clickMode then return end
        if not gui.Parent then return end

        local target = Mouse.Target
        if not target then return end
        local node = target
        local pm = getPlayerModels()
        while node and node.Parent ~= pm do node = node.Parent end
        if not node or not pm then return end
        if not isBlueprint(node) then return end

        local pl = collectMatchingPlanks()
        if #pl == 0 then setStatus("No matching planks available"); return end
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local entry = pl[1]
        local tag = isHoldMode() and "HOLD" or "TP"
        setStatus(string.format("Click [%s]: %s", tag, node.Name))
        task.spawn(function()
            local ok = doFill(node, entry, root)
            setHoldCount()
            if ok then setStatus("Filled " .. node.Name)
            else setStatus("Fill failed") end
        end)
    end)
end

local pickMode = false
local pickConn = nil
local pickBtnHandle = nil

local function stopPickMode()
    pickMode = false
    if pickConn then pickConn:Disconnect(); pickConn = nil end
    if pickBtnHandle then pcall(function() pickBtnHandle.Text = "Pick Plank" end) end
end

local function startPickMode()
    if pickMode then stopPickMode(); return end
    pickMode = true
    if pickBtnHandle then pickBtnHandle.Text = "Click a plank..." end

    pickConn = UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not pickMode then return end

        local target = Mouse.Target
        if not target then return end
        local node = target
        local pm = getPlayerModels()
        while node and node.Parent ~= pm do node = node.Parent end
        if not node or not pm then stopPickMode(); return end
        if not isLoosePlank(node) then setStatus("Not a matching plank"); stopPickMode(); return end
        local tc = plankTreeClass(node)
        if tc then
            selectedTreeClass = tc
            setStatus("Picked Wood Type=" .. tc)
            if woodTypeDropdown then pcall(function() woodTypeDropdown:Set(tc) end) end
            if treeLabelPara then pcall(function() treeLabelPara:setDesc(treeLabelPara, tc) end) end
        end
        stopPickMode()
    end)
end

local function updateInventory()
    local byTree, total = scanPlanks()
    if inventoryPara then
        if total == 0 then
            pcall(function() inventoryPara:setDesc(inventoryPara, "(no loose planks available)") end)
        else
            local parts = {}
            for tc, data in pairs(byTree) do
                local sizeParts = {}
                for s, c in pairs(data.sizes) do table.insert(sizeParts, s .. "x" .. c) end
                table.sort(sizeParts)
                table.insert(parts, string.format("%s(%d): %s", tc, data.count, table.concat(sizeParts, ",")))
            end
            table.sort(parts)
            pcall(function()
                inventoryPara:setDesc(inventoryPara, "Total: " .. total .. "  |  " .. table.concat(parts, "  "))
            end)
        end
    end
    if woodTypeDropdown then pcall(function() woodTypeDropdown:SetValues(getWoodTypeOptions(byTree)) end) end
    if playerDropdown then pcall(function() playerDropdown:SetValues(getPlayerOptions()) end) end
    if woodOwnerDropdown then pcall(function() woodOwnerDropdown:SetValues(getPlayerOptions()) end) end
    if baseDropdown then pcall(function() baseDropdown:SetValues(getBaseOwnerOptions()) end) end
    setHoldCount()
end

local function collectCurrentSettings()
    return {
        fillDelay = fillDelay,
        filterMinY = filterMinY,
        filterMaxY = filterMaxY,
        selectedTreeClass = selectedTreeClass,
        selectedPlayerName = selectedPlayer and selectedPlayer.Name or "(Me)",
        selectedWoodOwnerName = selectedWoodOwner and selectedWoodOwner.Name or "(Me)",
        selectedBaseOwner = selectedBaseOwner,
        fillMethod = fillMethod,
        holdFireInterval = HOLD_FIRE_INTERVAL,
        fireEveryFrame = fireEveryFrame,
        fireOnceOnly = fireOnceOnly,
        fireSignature = fireSignature,
    }
end

local function resetSettings()
    fillDelay = 0.15
    filterMinY = 0
    filterMaxY = 1000
    selectedTreeClass = nil
    selectedPlayer = plr
    selectedWoodOwner = plr
    selectedBaseOwner = nil
    fillMethod = "Testing/WIP"
    HOLD_FIRE_INTERVAL = 0.5
    fireEveryFrame = false
    fireOnceOnly = false
    fireSignature = 1

    if writefile and isfile then
        pcall(function()
            if isfile(SETTINGS_FILE) then writefile(SETTINGS_FILE, "{}") end
        end)
    end

    if playerDropdown then pcall(function() playerDropdown:Set("(Me)") end) end
    if woodOwnerDropdown then pcall(function() woodOwnerDropdown:Set("(Me)") end) end
    if woodTypeDropdown then pcall(function() woodTypeDropdown:Set("(All)") end) end
    updateCrossWarn()
    updateInventory()
    setStatus("Settings reset to defaults")
end

-- ─────────── BUILD CONTENT (ordered to match tabs) ───────────
local order = 0
local function nextOrder() order += 1; return order end

-- ═══ TARGET TAB ═══
makeSection("TARGET", nextOrder(), "target")

playerDropdown = makeDropdown("Fill Blueprints Of", getPlayerOptions(),
    selectedPlayer.Name or "(Me)", function(opt)
        if opt == "(Me)" then selectedPlayer = plr
        else selectedPlayer = Players:FindFirstChild(opt) or plr end
        setStatus("Blueprint owner: " .. selectedPlayer.Name)
    end, nextOrder())

woodOwnerDropdown = makeDropdown("Use Wood From", getPlayerOptions(),
    selectedWoodOwner.Name or "(Me)", function(opt)
        if opt == "(Me)" then selectedWoodOwner = plr
        else selectedWoodOwner = Players:FindFirstChild(opt) or plr end
        setStatus("Wood source: " .. selectedWoodOwner.Name)
        updateCrossWarn()
        updateInventory()
    end, nextOrder())

crossWarnPara = makeParagraph("Wood Source Info",
    selectedWoodOwner == plr and "Wood source: yourself (grabs will work)."
    or ("WARNING: Wood source is " .. selectedWoodOwner.Name .. " - may fail without perms."),
    nextOrder(),
    selectedWoodOwner == plr and TEXT_GRAY or WARN_RED)

woodTypeDropdown = makeDropdown("Wood Type", getWoodTypeOptions(nil),
    selectedTreeClass or "(All)", function(opt)
        if opt == "(All)" then selectedTreeClass = nil else selectedTreeClass = opt end
        if treeLabelPara then pcall(function() treeLabelPara:setDesc(treeLabelPara, opt) end) end
        setStatus("Wood type: " .. opt)
    end, nextOrder())

makeButton("Refresh Players",
    "Rescan the server for players (all dropdowns update)",
    function()
        if playerDropdown then pcall(function() playerDropdown:SetValues(getPlayerOptions()) end) end
        if woodOwnerDropdown then pcall(function() woodOwnerDropdown:SetValues(getPlayerOptions()) end) end
        if baseDropdown then pcall(function() baseDropdown:SetValues(getBaseOwnerOptions()) end) end
        setStatus("Refreshed dropdowns")
    end, nextOrder())

-- ═══ PLANKS TAB ═══
makeSection("PLANK SOURCE", nextOrder(), "planks")

pickBtnHandle = makeButton("Pick Plank",
    "Click a loose plank in the world to set the target wood type",
    function() startPickMode() end, nextOrder())

treeLabelPara = makeParagraph("Selected Wood Type",
    selectedTreeClass or "None (all types)", nextOrder())

makeInput("Min Y Size", tostring(filterMinY), function(t)
    local n = tonumber(t); if n then filterMinY = n end
end, nextOrder())

makeInput("Max Y Size", tostring(filterMaxY), function(t)
    local n = tonumber(t); if n then filterMaxY = n end
end, nextOrder())

makeSlider("Fill Delay (s)", 0.05, 0.5, fillDelay, function(v) fillDelay = v end, nextOrder())

-- ═══ FILL TAB ═══
makeSection("FILL METHOD", nextOrder(), "fill")

makeDropdown("Mode", fillMethodLabels,
    fillMethod == "Working" and "Working (teleport)" or "Testing/WIP (hold)",
    function(opt)
        if opt == "Working (teleport)" then
            fillMethod = "Working"
            setStatus("Mode: Working (teleport)")
        else
            fillMethod = "Testing/WIP"
            setStatus("Mode: Testing/WIP (hold)")
        end
    end, nextOrder())

makeSection("MODES", nextOrder())

makeButton("Auto Fill All",
    "One-shot fill of every target blueprint using the current mode",
    function() fillAllBlueprints() end, nextOrder())

makeButton("Fill Nearest BP",
    "Fill whichever of your blueprints is closest to you right now",
    function() fillNearestBlueprint() end, nextOrder())

makeToggle("Auto Fill Nearest",
    "Automatically fill the nearest blueprint every few seconds",
    false, function(state)
        nearestMode = state
        setStatus(state and "Auto-fill-nearest ON" or "Auto-fill-nearest OFF")
    end, nextOrder())

makeToggle("Loop Mode",
    "Continuously fill blueprints as new planks appear",
    false, function(state)
        loopMode = state
        setStatus(state and "Loop ON" or "Loop OFF")
    end, nextOrder())

clickToggleHandle = makeToggle("Click to Fill",
    "Click a blueprint to fill it with one matching plank",
    false, function(state)
        if state then startClickMode() else stopClickMode() end
        setStatus(state and "Click ON" or "Click OFF")
    end, nextOrder())

holdCountPara = makeParagraph("Held Planks", "Currently holding: 0 planks", nextOrder())

makeButton("Release All",
    "Stop holding every plank (only matters in Testing/WIP mode)",
    function()
        local count = holdCount()
        stopAllHolds()
        setHoldCount()
        setStatus("Released " .. count .. " plank(s)")
    end, nextOrder())

makeSection("HOLD TUNING (WIP ONLY)", nextOrder())

local fireSigDefaultText
if fireSignature == 1 then fireSigDefaultText = "1) Model only"
elseif fireSignature == 2 then fireSigDefaultText = "2) Model + CFrame"
elseif fireSignature == 3 then fireSigDefaultText = "3) Model + CFrame + true"
elseif fireSignature == 4 then fireSigDefaultText = "4) Model + Vector3"
else fireSigDefaultText = "5) Model + Mouse.Hit" end

makeDropdown("Fire Signature", getFireSigOptions(), fireSigDefaultText, function(opt)
    local n = tonumber(string.match(opt, "^(%d+)"))
    if n then fireSignature = n; setStatus("Fire signature: " .. opt) end
end, nextOrder())

makeSlider("Fire Interval (s)", 0.1, 1.0, HOLD_FIRE_INTERVAL, function(v)
    HOLD_FIRE_INTERVAL = v
    setStatus(string.format("Fire rate: %.3fs", v))
end, nextOrder())

makeToggle("Fire Every Frame",
    "Max hold strength (fires ClientIsDragging every render frame)",
    fireEveryFrame, function(state)
        fireEveryFrame = state
        setStatus(state and "Frame-spam ON" or "Frame-spam OFF")
    end, nextOrder())

makeToggle("Fire Once Only",
    "Only fire ClientIsDragging on grab. No repeat fires afterward.",
    fireOnceOnly, function(state)
        fireOnceOnly = state
        setStatus(state and "Fire-once mode ON" or "Fire-once mode OFF")
    end, nextOrder())

-- ═══ NAV TAB ═══
makeSection("NAVIGATION", nextOrder(), "nav")

makeButton("Fly",
    "Toggle flight. WASD + Space/Shift on PC. On-screen buttons on mobile.",
    function()
        if flying then stopFly(); setStatus("Fly OFF")
        else startFly(); setStatus("Fly ON") end
    end, nextOrder())

makeSlider("Fly Speed", 20, 200, flySpeed, function(v)
    flySpeed = v
    if flyBV and flyBV.Velocity.Magnitude > 0 then
        flyBV.Velocity = flyBV.Velocity.Unit * flySpeed
    end
end, nextOrder())

makeButton("TP to Closest BP",
    "Teleport to the nearest blueprint owned by the selected player",
    function() tpToClosestBP() end, nextOrder())

baseDropdown = makeDropdown("Base (Owner)", getBaseOwnerOptions(),
    selectedBaseOwner or "(pick one)", function(opt)
        selectedBaseOwner = opt
        setStatus("Base target: " .. opt)
    end, nextOrder())

makeButton("TP to Base",
    "Teleport to the selected player's base",
    function() tpToBase() end, nextOrder())

makeButton("Refresh Bases",
    "Rescan PlayerModels for owner entries",
    function()
        if baseDropdown then pcall(function() baseDropdown:SetValues(getBaseOwnerOptions()) end) end
        setStatus("Base list refreshed")
    end, nextOrder())

-- ═══ CONFIG TAB ═══
makeSection("CONFIG", nextOrder(), "config")

makeButton("Save Settings",
    "Write current settings to disk (persists across re-executions)",
    function()
        local ok, msg = trySaveSettings(collectCurrentSettings())
        if ok then setStatus("Settings saved")
        else setStatus("Save failed: " .. tostring(msg)) end
    end, nextOrder())

makeButton("Reset to Defaults",
    "Wipe everything back to defaults",
    function() resetSettings() end, nextOrder())

-- ═══ DEBUG TAB (owner only) ═══
if IS_OWNER then
    makeSection("DEBUG / SNIFFER (owner only)", nextOrder(), "debug")

    _G._BPFDragSniffing = false
    _G._BPFSnifferInstalled = false

    local function logArgs(tag, args)
        print(string.format("[SNIFF] %s  argCount=%d", tag, #args))
        for i = 1, #args do
            local v = args[i]
            print(string.format("   [%d] type=%s  value=%s", i, typeof(v), tostring(v)))
        end
    end

    local function installDragSniffer()
        if not ClientIsDragging then return false, "remote not found" end
        if _G._BPFSnifferInstalled then return true, "already installed" end
        if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
            local ok = pcall(function()
                local oldNamecall
                oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    if not _G._BPFDragSniffing then return oldNamecall(self, ...) end
                    local method = getnamecallmethod()
                    if self == ClientIsDragging then
                        logArgs("ClientIsDragging:" .. tostring(method), { ... })
                    end
                    return oldNamecall(self, ...)
                end)
            end)
            if ok then _G._BPFSnifferInstalled = true; return true, "installed" end
        end
        return false, "no hook available"
    end

    local sniffStatusPara = makeParagraph("Sniffer Status", "Not installed", nextOrder())

    makeButton("Install Sniffer",
        "WARNING: may break teleport until rejoin",
        function()
            local ok, msg = installDragSniffer()
            pcall(function()
                sniffStatusPara:setDesc(sniffStatusPara,
                    (ok and "Installed: " or "FAILED: ") .. tostring(msg))
            end)
            setStatus(ok and "Sniffer installed" or ("Sniffer failed: " .. tostring(msg)))
        end, nextOrder())

    makeToggle("Sniff Drag Remote", "Log ClientIsDragging calls", false, function(state)
        if state and not _G._BPFSnifferInstalled then
            setStatus("Install the sniffer first"); return
        end
        _G._BPFDragSniffing = state
        setStatus(state and "Sniffer ON" or "Sniffer OFF")
    end, nextOrder())

    makeButton("Print All Interaction Remotes", "Dump remote names", function()
        if not Interaction then return end
        print("=== Interaction remotes ===")
        for _, c in ipairs(Interaction:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                print("  " .. c.ClassName .. ": " .. c.Name)
            end
        end
    end, nextOrder())
end

-- ═══ LOG TAB ═══
makeSection("CONSOLE (LIVE OUTPUT)", nextOrder(), "log")

local consoleHolder = Instance.new("Frame")
consoleHolder.Size = UDim2.new(1, 0, 0, 180)
consoleHolder.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
consoleHolder.BorderSizePixel = 0
consoleHolder.LayoutOrder = nextOrder()
consoleHolder.Parent = body
Instance.new("UICorner", consoleHolder).CornerRadius = UDim.new(0, 6)
local chStroke = Instance.new("UIStroke", consoleHolder)
chStroke.Color = Color3.fromRGB(40, 40, 55)
chStroke.Thickness = 1

local consoleScroll = Instance.new("ScrollingFrame")
consoleScroll.Size = UDim2.new(1, -8, 1, -8)
consoleScroll.Position = UDim2.fromOffset(4, 4)
consoleScroll.BackgroundTransparency = 1
consoleScroll.BorderSizePixel = 0
consoleScroll.ScrollBarThickness = 4
consoleScroll.ScrollBarImageColor3 = ACCENT
consoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
consoleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
consoleScroll.Parent = consoleHolder

consoleLabel = Instance.new("TextLabel")
consoleLabel.Size = UDim2.new(1, -4, 0, 0)
consoleLabel.BackgroundTransparency = 1
consoleLabel.Text = #consoleLines > 0 and table.concat(consoleLines, "\n") or "(no output yet)"
consoleLabel.TextColor3 = Color3.fromRGB(180, 220, 180)
consoleLabel.Font = Enum.Font.Code
consoleLabel.TextSize = 10
consoleLabel.TextXAlignment = Enum.TextXAlignment.Left
consoleLabel.TextYAlignment = Enum.TextYAlignment.Top
consoleLabel.TextWrapped = true
consoleLabel.AutomaticSize = Enum.AutomaticSize.Y
consoleLabel.Parent = consoleScroll

makeButton("Clear Console", "Wipe the live log", function()
    consoleLines = {}
    if consoleLabel then consoleLabel.Text = "(cleared)" end
end, nextOrder())

makeButton("Copy Console to Clipboard", nil, function()
    local all = table.concat(consoleLines, "\n")
    local ok = pcall(function() if setclipboard then setclipboard(all) end end)
    if ok and setclipboard then setStatus("Copied") else setStatus("Clipboard unavailable") end
end, nextOrder())

makeSection("PLANK INVENTORY", nextOrder())
inventoryPara = makeParagraph("Loose Planks", "Scanning...", nextOrder())

makeButton("Rescan Now", nil, function()
    updateInventory()
    setStatus("Scanned")
end, nextOrder())

makeSection("STATUS", nextOrder())
statusPara = makeParagraph("Status", "Ready - mode: " .. fillMethod, nextOrder())

-- Create tab buttons
for _, def in ipairs(TAB_DEFS) do
    makeTabButton(def)
end

-- Set initial active tab
setActiveTab("target")

-- Update active tab based on scroll position
local lastScrollCheck = 0
RunService.Heartbeat:Connect(function()
    if not gui.Parent then return end
    if tick() - lastScrollCheck < 0.15 then return end
    lastScrollCheck = tick()

    local scrollY = body.CanvasPosition.Y
    local bodyTopAbsY = body.AbsolutePosition.Y
    local bestKey, bestDist = nil, math.huge

    for key, marker in pairs(sectionMarkers) do
        local markerRelY = (marker.AbsolutePosition.Y - bodyTopAbsY) + scrollY
        if markerRelY <= scrollY + 40 then
            local dist = (scrollY + 40) - markerRelY
            if markerRelY >= 0 and dist < bestDist then
                bestDist = dist
                bestKey = key
            end
        end
    end

    if bestKey and bestKey ~= activeTab then
        setActiveTab(bestKey)
    end
end)

-- ─────────── MIN / CLOSE / RESIZE ───────────
local minimized = false
local savedSize = panel.Size

local function togglePanel()
    minimized = not minimized
    if minimized then
        savedSize = panel.Size
        panel.Visible = false
    else
        panel.Visible = true
        panel.Size = savedSize
    end
end

toggleBtn.MouseButton1Click:Connect(togglePanel)

minimizeBtn.MouseButton1Click:Connect(function()
    minimized = true
    savedSize = panel.Size
    panel.Visible = false
end)

closeBtn.MouseButton1Click:Connect(function()
    stopAllHolds()
    stopFly()
    gui:Destroy()
    _G._BPFillerGui = nil
end)

local resizing = false
local resizeStartMouse, resizeStartSize

resizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        resizing = true
        resizeStartMouse = UIS:GetMouseLocation()
        resizeStartSize = panel.AbsoluteSize
    end
end)

UIS.InputChanged:Connect(function(input)
    if not resizing then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        local cur = UIS:GetMouseLocation()
        local dx = cur.X - resizeStartMouse.X
        local dy = cur.Y - resizeStartMouse.Y
        local newW = math.clamp(resizeStartSize.X + dx, 300, 700)
        local newH = math.clamp(resizeStartSize.Y + dy, 320, 900)
        panel.Size = UDim2.fromOffset(newW, newH)
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        resizing = false
    end
end)

-- ─────────── PLAYER REFRESH ───────────
Players.PlayerAdded:Connect(function()
    if playerDropdown then pcall(function() playerDropdown:SetValues(getPlayerOptions()) end) end
    if woodOwnerDropdown then pcall(function() woodOwnerDropdown:SetValues(getPlayerOptions()) end) end
    if baseDropdown then pcall(function() baseDropdown:SetValues(getBaseOwnerOptions()) end) end
end)

Players.PlayerRemoving:Connect(function(p)
    if selectedPlayer == p then
        selectedPlayer = plr
        if playerDropdown then pcall(function() playerDropdown:Set("(Me)") end) end
    end
    if selectedWoodOwner == p then
        selectedWoodOwner = plr
        if woodOwnerDropdown then pcall(function() woodOwnerDropdown:Set("(Me)") end) end
        updateCrossWarn()
    end
    if playerDropdown then pcall(function() playerDropdown:SetValues(getPlayerOptions()) end) end
    if woodOwnerDropdown then pcall(function() woodOwnerDropdown:SetValues(getPlayerOptions()) end) end
    if baseDropdown then pcall(function() baseDropdown:SetValues(getBaseOwnerOptions()) end) end
end)

-- ─────────── BACKGROUND ───────────
RunService.Heartbeat:Connect(function(dt)
    if not gui.Parent then return end
    lastScanAccum += dt
    if lastScanAccum >= SCAN_INTERVAL then
        lastScanAccum = 0
        updateInventory()
    end
end)

task.spawn(function()
    while gui.Parent do
        if loopMode then pcall(loopTick) end
        task.wait(1.5)
    end
end)

task.spawn(function()
    while gui.Parent do
        if nearestMode then pcall(fillNearestBlueprint) end
        task.wait(math.max(0.5, fillDelay * 3))
    end
end)

task.spawn(function()
    task.wait(0.5)
    pcall(updateInventory)
end)

task.spawn(function()
    while gui.Parent do
        task.wait(30)
        local ok = trySaveSettings(collectCurrentSettings())
        if not ok then break end
    end
end)

print("[BPFiller] v" .. VERSION .. " (Kron v2 UI) loaded.")
print("[BPFiller] Mode: " .. fillMethod .. "  |  Owner access: " .. tostring(IS_OWNER))
if savedSettings and next(savedSettings) then
    print("[BPFiller] Loaded saved settings.")
end
