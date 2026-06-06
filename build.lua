--// ==========================================
--//  BLUEPRINT BUILDER v7.5 — LINORIALIB COMPACT
--//  All features: Blueprint + Launcher + Autoplace + Autobuy + Server
--//  Buy speed: 0.01s | Visual effects | LinoriaLib
--//  Compact rectangle UI + Multi-plot support (position + raycast)
--//  GITHUB MODE: Per-plot blueprints auto-loaded from URLs
--//  LAUNCHER v3: Dynamic Player Detection | Live Target Validation | Auto-Cache Invalidation
--//  NEW: Mansion building added to all target/buy/autoplace lists
--// ==========================================

--// LOAD LINORIALIB
local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--// CONFIGURATION
local PLACE_DELAY = 0.25

--// GITHUB BLUEPRINT URLS (Plot 1-6)
local BLUEPRINT_URLS = {
    [1] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot1_20260602_220832.lua",
    [2] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot2_20260602_220832.lua",
    [3] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot3_20260602_215641.lua",
    [4] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot4_20260602_215951.lua",
    [5] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot5_20260602_221043.lua",
    [6] = "https://raw.githubusercontent.com/UnAliveScripts/blueprint/refs/heads/main/PlotExport_Plot6_20260602_222330.lua",
}

--// BLUEPRINT CACHE
local plotBlueprints = {}
local plotBlueprintNeeds = {}
local blueprintStatusLabel, blueprintRocketsLabel, blueprintBuildingsLabel

--// EFFECTS SETTINGS
local EFFECTS = {
    BeamColor = Color3.fromRGB(0, 255, 128),
    ParticleColor = Color3.fromRGB(100, 255, 150),
    GlowColor = Color3.fromRGB(0, 255, 200),
    PlaceSound = "rbxassetid://140477928605387",
    FinishSound = "rbxassetid://4989569018",
    BeamThickness = 0.15,
    BuildTime = 0.4,
}

--// REMOTES
local Remotes = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Remotes")
local LaunchAllMissiles = Remotes:WaitForChild("LaunchAllMissiles")
local PlaceItem = Remotes:WaitForChild("PlaceItem")
local PurchaseItem = Remotes:WaitForChild("PurchaseItem")
local HireWorker = Remotes:WaitForChild("HireWorker")

--// BUILD LOOKUP — MANSION ADDED
local BUILD_TYPES = {
    "Small House","Farm","Medium House","Large House","Greenhouse","Apartment",
    "Bank","Trade Port","Oil Rig","Factory","Industrial Factory",
    "Skyscraper","Power Plant","Anti Air","Basic AA Turret","Bubble Shield",
    "EMP Defense Tower","Flare Launcher","Laser Defense System",
    "Mansion" -- NEW
}

local ROCKET_NAMES = { 
    "Basic Missile","Vanta","Bazooka","Super Missile","Titan Missile",
    "Sparrow","Viper Missile","Hydra","AMG","Nuke","VX-9","VIP Launcher"
}

local WORKER_NAMES = { "Farmer","LavaBuilder","MissileEngineer","ProBuilder","RepairMan" }

local BUILD_SET = {}
for _, name in ipairs(BUILD_TYPES) do BUILD_SET[name] = true end

local ROCKET_SET = {}
for _, name in ipairs(ROCKET_NAMES) do ROCKET_SET[name] = true end

local WORKER_SET = {}
for _, name in ipairs(WORKER_NAMES) do WORKER_SET[name] = true end

--// ASSET SIZE LOOKUP
local ASSET_SIZES = {}

local function buildSizeLookup()
    local assets = ReplicatedStorage:FindFirstChild("Game")
    if not assets then return end
    assets = assets:FindFirstChild("Assets")
    if not assets then return end

    local missilesFolder = assets:FindFirstChild("Missiles")
    if missilesFolder then
        for _, missile in ipairs(missilesFolder:GetChildren()) do
            local size = missile:IsA("BasePart") and missile.Size or
                        (missile.PrimaryPart and missile.PrimaryPart.Size)
            if size then ASSET_SIZES[missile.Name] = size end
        end
    end

    local housesFolder = assets:FindFirstChild("Houses")
    if housesFolder then
        for _, house in ipairs(housesFolder:GetChildren()) do
            local size = house:IsA("BasePart") and house.Size or
                        (house.PrimaryPart and house.PrimaryPart.Size)
            if size then ASSET_SIZES[house.Name] = size end
        end
    end

    local defensesFolder = assets:FindFirstChild("Defenses")
    if defensesFolder then
        for _, defense in ipairs(defensesFolder:GetChildren()) do
            local size = defense:IsA("BasePart") and defense.Size or
                        (defense.PrimaryPart and defense.PrimaryPart.Size)
            if size then ASSET_SIZES[defense.Name] = size end
        end
    end

    local workersFolder = assets:FindFirstChild("Workers")
    if workersFolder then
        for _, worker in ipairs(workersFolder:GetChildren()) do
            local size = worker:IsA("BasePart") and worker.Size or
                        (worker.PrimaryPart and worker.PrimaryPart.Size)
            if size then ASSET_SIZES[worker.Name] = size end
        end
    end
end

buildSizeLookup()

--// ==========================================
--//  DYNAMIC BLUEPRINT LOADER (GITHUB)
--// ==========================================

local function resolvePlotNumber(plot)
    if not plot then return nil end
    local name = plot.Name
    
    local patterns = {
        "^Plot%s*(%d+)$",
        "^plot%s*(%d+)$",
        "^Base%s*(%d+)$",
        "^base%s*(%d+)$",
        "^(%d+)$",
        "Plot%s*(%d+)",
        "plot%s*(%d+)",
    }
    
    for _, pattern in ipairs(patterns) do
        local num = tonumber(name:match(pattern))
        if num and num >= 1 and num <= 6 then
            return num
        end
    end
    
    return nil
end

local function fetchBlueprint(url)
    local success, result = pcall(function()
        local content = game:HttpGet(url)
        return loadstring(content)()
    end)
    if success and type(result) == "table" then
        return result
    else
        warn("[BLUEPRINT] Fetch failed: " .. tostring(result))
        return nil
    end
end

local function computeBlueprintNeeds(bp)
    local needs = { rockets = {}, buildings = {}, workers = {} }
    for _, item in ipairs(bp) do
        local name = item.Name
        if ROCKET_SET[name] then
            needs.rockets[name] = (needs.rockets[name] or 0) + 1
        elseif BUILD_SET[name] then
            needs.buildings[name] = (needs.buildings[name] or 0) + 1
        elseif WORKER_SET[name] then
            needs.workers[name] = (needs.workers[name] or 0) + 1
        end
    end
    return needs
end

local function getBlueprintForPlot(plot)
    if not plot then return nil, nil end
    local plotName = plot.Name
    
    if plotBlueprints[plotName] then
        return plotBlueprints[plotName], plotBlueprintNeeds[plotName]
    end
    
    local plotNum = resolvePlotNumber(plot)
    if not plotNum then
        warn("[BLUEPRINT] Could not resolve plot number for: " .. plotName)
        return nil, nil
    end
    
    local url = BLUEPRINT_URLS[plotNum]
    if not url then
        warn("[BLUEPRINT] No URL for plot number: " .. plotNum)
        return nil, nil
    end
    
    Library:Notify('Loading blueprint for ' .. plotName .. '...', 2)
    local bp = fetchBlueprint(url)
    if bp then
        local needs = computeBlueprintNeeds(bp)
        plotBlueprints[plotName] = bp
        plotBlueprintNeeds[plotName] = needs
        if blueprintStatusLabel then
            blueprintStatusLabel:SetText('Items: ' .. #bp)
            local rCount = 0; for _ in pairs(needs.rockets) do rCount = rCount + 1 end
            local bCount = 0; for _ in pairs(needs.buildings) do bCount = bCount + 1 end
            blueprintRocketsLabel:SetText('Rockets: ' .. rCount)
            blueprintBuildingsLabel:SetText('Buildings: ' .. bCount)
        end
        Library:Notify('Loaded ' .. #bp .. ' items for ' .. plotName, 2)
        return bp, needs
    end
    
    return nil, nil
end

--// BLUEPRINT DATA (fallback empty)
local blueprint = {}
local blueprintNeeds = { rockets = {}, buildings = {}, workers = {} }

--// SETTINGS
local Settings = {
    LauncherEnabled = false,
    TargetPlayers = false,
    PrioritizeBigMeteor = false,
    FireDelay = 0.08,
    FireBatch = 1,
    MaxTargetRange = 2000,
    QueueMaxSize = 100,
    TargetBuildings = {},

    BlueprintEnabled = false,
    BlueprintRepair = false,

    AutoplaceEnabled = false,
    AutoplaceBuildings = false,
    PlaceDelay = 0.15,
    BuildingPlaceDelay = 0.3,
    CollisionRadius = 2,
    EdgeAvoidance = 3,
    MinimumSpacing = 2,
    AutoplaceRockets = {},
    AutoplaceRocketsList = {},
    AutoplaceBuildingsList = {},

    AutobuyEnabled = false,
    AutobuyRockets = false,
    AutobuyBuildings = false,
    AutobuyBuilding = "Small House",
    AutobuyWorkers = false,
    BuyDelay = 0.01,
    AutobuyRocketsList = {},
    AutobuyBuildingsList = {},
    AutobuyWorkersList = {},
}

for _, name in ipairs(BUILD_TYPES) do
    Settings.TargetBuildings[name] = true
    Settings.AutoplaceBuildingsList[name] = true
    Settings.AutobuyBuildingsList[name] = true
end
for _, name in ipairs(ROCKET_NAMES) do
    Settings.AutobuyRocketsList[name] = true
    Settings.AutoplaceRockets[name] = true
end
for _, name in ipairs(WORKER_NAMES) do
    Settings.AutobuyWorkersList[name] = true
end

--// STATE VARIABLES
local lastFire = 0
local lastPlace = 0
local lastPlaceBuilding = 0
local lastRocketBuy = 0
local lastBuildingBuy = 0
local lastWorkerBuy = 0
local lastTargetScan = 0
local targetQueue = {}
local cachedPlayerPlot = nil
local cachedPlotRefreshTime = 0
local cachedPlacedItems = {}
local cachedPlacedItemsRefresh = 0
local gridPosition = { idx = 0 }
local gridPositionBuildings = { idx = 0 }
local isPlacing = false
local heartbeatCounter = 0

local PlacementStats = { successCount = 0, failCount = 0, lastUpdate = 0 }

-- Launcher cache & tracking
local cachedTargets = {}
local cachedTargetsRefresh = 0
local launcherStatsLabel
local activePlotConnections = {}
local playerPlotMap = {}

-- Buy queues
local buyQueueRockets = {}
local buyQueueBuildings = {}
local buyQueueWorkers = {}

local function rebuildBuyQueues(specificNeeds)
    buyQueueRockets = {}
    buyQueueBuildings = {}
    buyQueueWorkers = {}

    local needs = specificNeeds or blueprintNeeds
    for name, count in pairs(needs.rockets) do
        for i = 1, count do table.insert(buyQueueRockets, name) end
    end
    for name, count in pairs(needs.buildings) do
        for i = 1, count do table.insert(buyQueueBuildings, name) end
    end
    for name, count in pairs(needs.workers) do
        for i = 1, count do table.insert(buyQueueWorkers, name) end
    end
end

rebuildBuyQueues()

--// ==========================================
--//  PLOT DETECTION — MULTI-PLOT SUPPORT
--// ==========================================

local function getOwnedPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local activePlots = plots:FindFirstChild("ActivePlots")
    if not activePlots then return nil end

    local playerName = LocalPlayer.Name
    local playerDisplayName = LocalPlayer.DisplayName

    for _, plot in ipairs(activePlots:GetChildren()) do
        local placementPart = plot:FindFirstChild("PlacementPart")
        if placementPart then
            local userInfoAttachment = placementPart:FindFirstChild("UserInfoAttachment")
            if userInfoAttachment then
                local userInfo = userInfoAttachment:FindFirstChild("UserInfo")
                if userInfo then
                    local card = userInfo:FindFirstChild("Card")
                    if card then
                        local info = card:FindFirstChild("Info")
                        if info then
                            local username = info:FindFirstChild("Username")
                            if username and (username.Text == playerName or username.Text == playerDisplayName) then
                                return plot
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function getPlotByPosition()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local pPos = hrp.Position
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local activePlots = plots:FindFirstChild("ActivePlots")
    if not activePlots then return nil end

    local bestPlot = nil
    local bestDist = math.huge

    for _, plot in ipairs(activePlots:GetChildren()) do
        local placementPart = plot:FindFirstChild("PlacementPart")
        if placementPart and placementPart:IsA("BasePart") then
            local pos = placementPart.Position
            local size = placementPart.Size

            local dx = pPos.X - pos.X
            local dz = pPos.Z - pos.Z
            local dy = pPos.Y - pos.Y
            local horizontalDist = math.sqrt(dx*dx + dz*dz)

            local inBoundsX = math.abs(dx) <= (size.X / 2) + 5
            local inBoundsZ = math.abs(dz) <= (size.Z / 2) + 5
            local inBoundsY = math.abs(dy) <= (size.Y / 2) + 1000

            if inBoundsX and inBoundsZ and inBoundsY then
                if horizontalDist < bestDist then
                    bestDist = horizontalDist
                    bestPlot = plot
                end
            end
        end
    end
    return bestPlot
end

local function getPlotByRaycast()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local rayOrigin = hrp.Position
    local rayDirection = Vector3.new(0, -1000, 0)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {char}

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if not result then return nil end

    local hitPart = result.Instance
    if not hitPart then return nil end

    local current = hitPart
    for _ = 1, 10 do
        if not current then break end
        local parent = current.Parent
        if not parent then break end

        if parent.Name == "ActivePlots" then
            return current
        end

        if parent.Name == "PlacedItems" then
            local plot = parent.Parent
            if plot and plot.Parent and plot.Parent.Name == "ActivePlots" then
                return plot
            end
        end

        current = parent
    end
    return nil
end

local function getClosestPlot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local pPos = hrp.Position
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local activePlots = plots:FindFirstChild("ActivePlots")
    if not activePlots then return nil end

    local bestPlot = nil
    local bestDist = 200

    for _, plot in ipairs(activePlots:GetChildren()) do
        local placementPart = plot:FindFirstChild("PlacementPart")
        if placementPart and placementPart:IsA("BasePart") then
            local pos = placementPart.Position
            local dx = pPos.X - pos.X
            local dz = pPos.Z - pos.Z
            local dist = math.sqrt(dx*dx + dz*dz)
            if dist < bestDist then
                bestDist = dist
                bestPlot = plot
            end
        end
    end
    return bestPlot
end

local function getCurrentPlot()
    local plot = getPlotByPosition()
    if plot then return plot end

    plot = getPlotByRaycast()
    if plot then return plot end

    plot = getClosestPlot()
    if plot then return plot end

    return getOwnedPlot()
end

local function getPlacementBounds(plot)
    local placementPart = plot:FindFirstChild("PlacementPart")
    if not placementPart or not placementPart:IsA("BasePart") then return nil end

    local pos = placementPart.Position
    local size = placementPart.Size
    local cf = placementPart.CFrame

    return {
        minX = pos.X - (size.X / 2),
        maxX = pos.X + (size.X / 2),
        minZ = pos.Z - (size.Z / 2),
        maxZ = pos.Z + (size.Z / 2),
        topY = pos.Y + (size.Y / 2),
        centerX = pos.X,
        centerZ = pos.Z,
        cframe = cf,
        position = pos,
        size = size,
    }
end

local function getPlotCenter(plot)
    local placementPart = plot:FindFirstChild("PlacementPart")
    if placementPart then return placementPart.Position end
    return plot:GetPivot().Position
end

local function getPlotRotation(plot)
    local placementPart = plot:FindFirstChild("PlacementPart")
    if placementPart then
        local _, ry, _ = placementPart.CFrame:ToEulerAnglesXYZ()
        return ry
    end
    return 0
end

--// ==========================================
--//  COORDINATE CONVERSION
--// ==========================================

local function worldToRelative(worldPos, plotBounds)
    if not plotBounds or not plotBounds.cframe then
        return worldPos.X - plotBounds.centerX, worldPos.Z - plotBounds.centerZ
    end
    local localPos = plotBounds.cframe:PointToObjectSpace(worldPos)
    return localPos.X, localPos.Z
end

local function relativeToWorld(relX, relZ, plotBounds)
    if not plotBounds or not plotBounds.cframe then
        return Vector3.new(plotBounds.centerX + relX, plotBounds.topY, plotBounds.centerZ + relZ)
    end
    local localPos = Vector3.new(relX, 0, relZ)
    return plotBounds.cframe:PointToWorldSpace(localPos)
end

--// ==========================================
--//  PLACEMENT LOGIC
--// ==========================================

local function getPlacedItems(plot)
    local placedItems = plot:FindFirstChild("PlacedItems")
    if not placedItems then return {} end

    local items = {}
    for _, item in ipairs(placedItems:GetChildren()) do
        if item:IsA("BasePart") then
            table.insert(items, {position = item.Position, size = item.Size})
        elseif item:IsA("Model") and item.PrimaryPart then
            table.insert(items, {position = item.PrimaryPart.Position, size = item.PrimaryPart.Size})
        end
    end
    return items
end

local function checkCollision(x, z, placedItems)
    local minDist = Settings.CollisionRadius + Settings.MinimumSpacing
    for _, item in ipairs(placedItems) do
        local dx = x - item.position.X
        local dz = z - item.position.Z
        local distSq = dx * dx + dz * dz
        local itemRadius = item.radius or math.sqrt((item.size.X / 2) ^ 2 + (item.size.Z / 2) ^ 2)
        if not item.radius then item.radius = itemRadius end
        local thresholdSq = (minDist + itemRadius) ^ 2
        if distSq < thresholdSq then return true end
    end
    return false
end

local function getGridPosition(bounds, placedItems, gridPos, itemName)
    if not bounds then return nil end
    gridPos = gridPos or gridPosition

    local padding = Settings.EdgeAvoidance
    local sizeX = bounds.maxX - bounds.minX
    local sizeZ = bounds.maxZ - bounds.minZ

    local minRelX = -(sizeX / 2) + padding
    local maxRelX = (sizeX / 2) - padding
    local minRelZ = -(sizeZ / 2) + padding
    local maxRelZ = (sizeZ / 2) - padding

    if minRelX >= maxRelX or minRelZ >= maxRelZ then return nil end

    local itemHalfWidth = 0.5
    local itemHalfDepth = 0.5
    if itemName and ASSET_SIZES[itemName] then
        local itemSize = ASSET_SIZES[itemName]
        itemHalfWidth = itemSize.X / 2
        itemHalfDepth = itemSize.Z / 2
    end

    local spacing = 2.5
    if itemName and ASSET_SIZES[itemName] then
        local itemSize = ASSET_SIZES[itemName]
        local maxDim = math.max(itemSize.X, itemSize.Z)
        spacing = maxDim + 2.5
    end

    local idx = gridPos.idx or 0
    local relX, relZ = 0, 0

    if idx == 0 then
        relX, relZ = 0, 0
    else
        local layer = 0
        local remaining = idx
        while remaining > layer * 8 do
            remaining = remaining - layer * 8
            layer = layer + 1
        end
        local s = layer * spacing
        local pos = remaining
        if pos <= layer then
            relX = (pos - 1) * spacing - (layer - 1) * spacing
            relZ = -s
        elseif pos <= 2 * layer then
            relX = s
            relZ = -s + (pos - layer) * spacing
        elseif pos <= 3 * layer then
            relX = s - (pos - 2 * layer) * spacing
            relZ = s
        else
            relX = -s
            relZ = s - (pos - 3 * layer) * spacing
        end
    end

    if relX - itemHalfWidth < minRelX or relX + itemHalfWidth > maxRelX or 
       relZ - itemHalfDepth < minRelZ or relZ + itemHalfDepth > maxRelZ then
        gridPos.idx = idx + 1
        return nil
    end

    local worldX = bounds.centerX + relX
    local worldZ = bounds.centerZ + relZ

    if not checkCollision(worldX, worldZ, placedItems) then
        gridPos.idx = idx + 1
        return relX, relZ
    end

    gridPos.idx = idx + 1
    return nil
end

local function canPlace()
    return tick() - lastPlace >= Settings.PlaceDelay
end

local function canPlaceBuilding()
    return tick() - lastPlaceBuilding >= Settings.BuildingPlaceDelay
end

local function getSelectedRocket()
    local selected = {}
    for name, enabled in pairs(Settings.AutoplaceRockets) do
        if enabled then table.insert(selected, name) end
    end
    return #selected > 0 and selected[math.random(#selected)] or nil
end

local function getSelectedBuilding()
    local selected = {}
    for name, enabled in pairs(Settings.AutoplaceBuildingsList) do
        if enabled then table.insert(selected, name) end
    end
    return #selected > 0 and selected[math.random(#selected)] or nil
end

--// AUTO-PLACE ROCKETS
local function placeRocketAuto()
    if not canPlace() then return end

    local rocketType = getSelectedRocket()
    if not rocketType then return end

    if not cachedPlayerPlot or tick() - cachedPlotRefreshTime > 5 then
        cachedPlayerPlot = getCurrentPlot()
        cachedPlotRefreshTime = tick()
        cachedPlacedItemsRefresh = 0
        gridPosition = { idx = 0 }
    end
    if not cachedPlayerPlot then return end

    local bounds = getPlacementBounds(cachedPlayerPlot)
    if not bounds then return end

    if tick() - cachedPlacedItemsRefresh > 1 then
        cachedPlacedItems = getPlacedItems(cachedPlayerPlot)
        cachedPlacedItemsRefresh = tick()
    end

    for _ = 1, 5 do
        local relX, relZ = getGridPosition(bounds, cachedPlacedItems, gridPosition, rocketType)
        if relX then
            lastPlace = tick()
            pcall(function()
                PlaceItem:FireServer(rocketType, relX, relZ, 0)
                table.insert(cachedPlacedItems, {
                    position = Vector3.new(bounds.centerX + relX, bounds.topY, bounds.centerZ + relZ),
                    size = ASSET_SIZES[rocketType] or Vector3.new(1,1,1)
                })
            end)
            PlacementStats.successCount = PlacementStats.successCount + 1
            PlacementStats.lastUpdate = tick()
            return
        end
    end
    PlacementStats.failCount = PlacementStats.failCount + 1
    PlacementStats.lastUpdate = tick()
end

--// AUTO-PLACE BUILDINGS
local function placeBuildingAuto()
    if not canPlaceBuilding() then return end

    local buildingType = getSelectedBuilding()
    if not buildingType then return end

    if not cachedPlayerPlot or tick() - cachedPlotRefreshTime > 5 then
        cachedPlayerPlot = getCurrentPlot()
        cachedPlotRefreshTime = tick()
        cachedPlacedItemsRefresh = 0
        gridPositionBuildings = { idx = 0 }
    end
    if not cachedPlayerPlot then return end

    local bounds = getPlacementBounds(cachedPlayerPlot)
    if not bounds then return end

    if tick() - cachedPlacedItemsRefresh > 1 then
        cachedPlacedItems = getPlacedItems(cachedPlayerPlot)
        cachedPlacedItemsRefresh = tick()
    end

    for _ = 1, 5 do
        local relX, relZ = getGridPosition(bounds, cachedPlacedItems, gridPositionBuildings, buildingType)
        if relX then
            lastPlaceBuilding = tick()
            pcall(function()
                PlaceItem:FireServer(buildingType, relX, relZ, 0)
                table.insert(cachedPlacedItems, {
                    position = Vector3.new(bounds.centerX + relX, bounds.topY, bounds.centerZ + relZ),
                    size = ASSET_SIZES[buildingType] or Vector3.new(1,1,1)
                })
            end)
            return
        end
    end
end

--// ==========================================
--//  SMART AUTOBUY (0.01s)
--// ==========================================

local autobuyRocketIndex = 1
local autobuyWorkerIndex = 1

local function getNextRocket()
    local selected = {}
    for name, enabled in pairs(Settings.AutobuyRocketsList) do
        if enabled then table.insert(selected, name) end
    end
    if #selected == 0 then return nil end
    local rocket = selected[autobuyRocketIndex]
    autobuyRocketIndex = autobuyRocketIndex % #selected + 1
    return rocket
end

local function getNextWorker()
    local selected = {}
    for name, enabled in pairs(Settings.AutobuyWorkersList) do
        if enabled then table.insert(selected, name) end
    end
    if #selected == 0 then return nil end
    local worker = selected[autobuyWorkerIndex]
    autobuyWorkerIndex = autobuyWorkerIndex % #selected + 1
    return worker
end

local function smartAutoBuy()
    if Settings.AutobuyRockets and #buyQueueRockets > 0 and tick() - lastRocketBuy >= Settings.BuyDelay then
        local rocket = table.remove(buyQueueRockets, 1)
        local success, err = pcall(function()
            PurchaseItem:FireServer(rocket)
        end)
        if success then
            print("[BUY] Rocket: " .. rocket .. " | Left: " .. #buyQueueRockets)
        else
            warn("[BUY] Failed: " .. tostring(err))
            table.insert(buyQueueRockets, 1, rocket)
        end
        lastRocketBuy = tick()
    end

    if Settings.AutobuyBuildings and #buyQueueBuildings > 0 and tick() - lastBuildingBuy >= Settings.BuyDelay then
        local building = table.remove(buyQueueBuildings, 1)
        local success, err = pcall(function()
            PurchaseItem:FireServer(building)
        end)
        if success then
            print("[BUY] Building: " .. building .. " | Left: " .. #buyQueueBuildings)
        else
            warn("[BUY] Failed: " .. tostring(err))
            table.insert(buyQueueBuildings, 1, building)
        end
        lastBuildingBuy = tick()
    end

    if Settings.AutobuyWorkers and #buyQueueWorkers > 0 and tick() - lastWorkerBuy >= Settings.BuyDelay then
        local worker = table.remove(buyQueueWorkers, 1)
        local success, err = pcall(function()
            HireWorker:FireServer(worker)
        end)
        if success then
            print("[BUY] Worker: " .. worker .. " | Left: " .. #buyQueueWorkers)
        else
            warn("[BUY] Failed: " .. tostring(err))
            table.insert(buyQueueWorkers, 1, worker)
        end
        lastWorkerBuy = tick()
    end
end

--// LAUNCH LOGIC
local function queueTargets(positions)
 if not positions or #positions == 0 then return end

 for _, pos in ipairs(positions) do
 table.insert(targetQueue, pos)
 end
end

local function fireNextTarget()
 if #targetQueue == 0 then return end
 if tick() - lastFire < Settings.FireDelay then return end

 for _ = 1, math.max(1, math.floor(Settings.FireBatch or 1)) do
 if #targetQueue == 0 then break end
 local pos = table.remove(targetQueue, 1)
 lastFire = tick()

 pcall(function()
 LaunchAllMissiles:FireServer(pos)
 end)
 end
end

--// SERVER FUNCTIONS
local function rejoinServer()
 TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

local function newServer()
 local success, servers = pcall(function()
 return HttpService:JSONDecode(game:HttpGet(
 "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
 ))
 end)

 if success and servers and servers.data then
 for _, server in pairs(servers.data) do
 if server.playing < server.maxPlayers then
 TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
 return
 end
 end
 end

 -- fallback
 TeleportService:Teleport(game.PlaceId)
end

local function joinServerWith56Players()
 local success, servers = pcall(function()
 return HttpService:JSONDecode(game:HttpGet(
 "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
 ))
 end)

 if success and servers and servers.data then
 for _, server in pairs(servers.data) do
 if (server.playing == 5 or server.playing == 6) and server.playing < server.maxPlayers then
 TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
 return
 end
 end
 end

 -- If no 5/6 player server found, join any available
 newServer()
end

--// CLEANUP
local function disableAllToggles()
 Settings.LauncherEnabled = false
 Settings.AutoplaceEnabled = false
 Settings.AutoplaceBuildings = false
 Settings.AutobuyRockets = false
 Settings.AutobuyBuildings = false
 Settings.TargetPlayers = false
 targetQueue = {}
 PlacementStats.successCount = 0
 PlacementStats.failCount = 0
end

--// CHECKS
local function hasForcefield(plot)
 local forcefieldMesh = plot:FindFirstChild("forcefieldmesh", true)
 if forcefieldMesh and forcefieldMesh:IsA("BasePart") then
 return forcefieldMesh.Transparency == 0 or forcefieldMesh.CanQuery == true
 end
 return false
end

local function isOwnPlot(plot)
 local placementPart = plot:FindFirstChild("PlacementPart")
 if not placementPart then return false end

 local userInfoAttachment = placementPart:FindFirstChild("UserInfoAttachment")
 if not userInfoAttachment then return false end

 local userInfo = userInfoAttachment:FindFirstChild("UserInfo")
 if not userInfo then return false end

 local card = userInfo:FindFirstChild("Card")
 if not card then return false end

 local info = card:FindFirstChild("Info")
 if not info then return false end

 local username = info:FindFirstChild("Username")
 if not username or username.Text == "" then return false end

 return username.Text == LocalPlayer.Name or username.Text == LocalPlayer.DisplayName
end

--// TARGETING
local function getPlayerTargets()
 local targets = {}
 local currentTime = tick()

 for _, player in ipairs(Players:GetPlayers()) do
 if player == LocalPlayer or not player.Parent then continue end

 local character = player.Character
 if not character or not character.Parent then continue end

 local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
 if not humanoidRootPart or not humanoidRootPart.Parent then continue end

 local humanoid = character:FindFirstChild("Humanoid")
 if not humanoid or humanoid.Health <= 0 then continue end

 local shieldAttack = player:GetAttribute("BaseShieldAttackCancelableExpiresAt") or 0
 local forcefield = player:GetAttribute("ForcefieldExpiresAt") or 0
 local protection = player:GetAttribute("ProtectionExpiresAt") or 0
 local newPlayer = player:GetAttribute("NewPlayerForcefieldEndsAt") or 0

 if shieldAttack > currentTime or forcefield > currentTime or protection > currentTime or newPlayer > currentTime then
 continue
 end

 table.insert(targets, humanoidRootPart.Position)
 end

 return targets
end

local cachedTargets = {}
local cachedTargetsRefresh = 0

local function scanAllTargets()
 local allTargets = {}

 local meteorVisuals = workspace:FindFirstChild("_MeteorShowerVisuals")
 local bigMeteorFound = false
 if meteorVisuals then
 local bigMeteor = meteorVisuals:FindFirstChild("BigMeteor")
 if bigMeteor and bigMeteor.Parent then
 local meteorPos = bigMeteor:IsA("BasePart") and bigMeteor.Position
 or (bigMeteor.PrimaryPart and bigMeteor.PrimaryPart.Position)
 if meteorPos then
 table.insert(allTargets, meteorPos)
 bigMeteorFound = true
 end
 end
 end

 if Settings.PrioritizeBigMeteor and bigMeteorFound then
 return allTargets
 end

 local plots = workspace:FindFirstChild("Plots")
 if plots then
 local activePlots = plots:FindFirstChild("ActivePlots")
 if activePlots then
 for _, plot in ipairs(activePlots:GetChildren()) do
 if not plot.Parent then continue end
 if hasForcefield(plot) or isOwnPlot(plot) then continue end

 local placedItems = plot:FindFirstChild("PlacedItems")
 if placedItems and #placedItems:GetChildren() > 0 then
 for _, obj in ipairs(placedItems:GetChildren()) do
 if not obj.Parent then continue end
 if BUILD_SET[obj.Name] and Settings.TargetBuildings[obj.Name] then
 local pos = nil
 if obj:IsA("BasePart") then
 pos = obj.Position
 elseif obj:IsA("Model") and obj.PrimaryPart then
 pos = obj.PrimaryPart.Position
 end
 if pos then
 table.insert(allTargets, pos)
 end
 end
 end
 end
 end
 end
 end

 if Settings.TargetPlayers then
 local playerTargets = getPlayerTargets()
 for _, pos in ipairs(playerTargets) do
 table.insert(allTargets, pos)
 end
 end

 return allTargets
end

--// NEW PLAYER DETECTION
Players.PlayerAdded:Connect(function(player)
 print("[PLAYER] Joined: " .. player.Name)
end)

Players.PlayerRemoving:Connect(function(player)
 print("[PLAYER] Left: " .. player.Name)
end)

--// SERVER FUNCTIONS
local function rejoinServer()
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

local function newServer()
    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        ))
    end)

    if success and servers and servers.data then
        for _, server in pairs(servers.data) do
            if server.playing < server.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
                return
            end
        end
    end
    TeleportService:Teleport(game.PlaceId)
end

local function joinServerWith56Players()
    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        ))
    end)

    if success and servers and servers.data then
        for _, server in pairs(servers.data) do
            if (server.playing == 5 or server.playing == 6) and server.playing < server.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
                return
            end
        end
    end
    newServer()
end

--// CLEANUP
local function disableAllToggles()
    Settings.LauncherEnabled = false
    Settings.AutoplaceEnabled = false
    Settings.AutoplaceBuildings = false
    Settings.AutobuyRockets = false
    Settings.AutobuyBuildings = false
    Settings.TargetPlayers = false
    targetQueue = {}
    cachedTargets = {}
    PlacementStats.successCount = 0
    PlacementStats.failCount = 0
end

--// ==========================================
--//  VISUAL EFFECTS
--// ==========================================

local function createGlowPart(position, size)
    local glow = Instance.new("Part")
    glow.Shape = Enum.PartType.Ball
    glow.Size = Vector3.new(0.5, 0.5, 0.5)
    glow.Position = position
    glow.Anchored = true
    glow.CanCollide = false
    glow.Material = Enum.Material.Neon
    glow.Color = EFFECTS.GlowColor
    glow.Transparency = 0.3
    glow.Parent = workspace
    TweenService:Create(glow, TweenInfo.new(EFFECTS.BuildTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(size.X * 2, size.Y * 2, size.Z * 2), Transparency = 1
    }):Play()
    Debris:AddItem(glow, EFFECTS.BuildTime + 0.1)
end

local function createParticleBurst(position)
    local attachment = Instance.new("Attachment")
    attachment.WorldPosition = position
    attachment.Parent = workspace.Terrain
    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new(EFFECTS.ParticleColor, Color3.fromRGB(255, 255, 255))
    emitter.Size = NumberSequence.new(0.5, 0)
    emitter.Transparency = NumberSequence.new(0, 1)
    emitter.Lifetime = NumberRange.new(0.5, 1)
    emitter.Rate = 0
    emitter.Speed = NumberRange.new(5, 10)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Acceleration = Vector3.new(0, -20, 0)
    emitter.Drag = 2
    emitter.Parent = attachment
    emitter:Emit(20)
    task.delay(1.5, function() attachment:Destroy() end)
end

local function createBuildBeam(targetPosition)
    local startPart = Instance.new("Part")
    startPart.Anchored = true; startPart.CanCollide = false; startPart.Transparency = 1
    startPart.Size = Vector3.new(1, 1, 1)
    startPart.Position = targetPosition + Vector3.new(0, 50, 0)
    startPart.Parent = workspace

    local endPart = Instance.new("Part")
    endPart.Anchored = true; endPart.CanCollide = false; endPart.Transparency = 1
    endPart.Size = Vector3.new(1, 1, 1)
    endPart.Position = targetPosition
    endPart.Parent = workspace

    local beam = Instance.new("Beam")
    beam.Color = ColorSequence.new(EFFECTS.BeamColor)
    beam.Width0 = EFFECTS.BeamThickness
    beam.Width1 = EFFECTS.BeamThickness * 3
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Attachment0 = Instance.new("Attachment", startPart)
    beam.Attachment1 = Instance.new("Attachment", endPart)
    beam.Parent = startPart

    TweenService:Create(beam, TweenInfo.new(EFFECTS.BuildTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Width0 = 0, Width1 = 0
    }):Play()

    Debris:AddItem(startPart, EFFECTS.BuildTime + 0.1)
    Debris:AddItem(endPart, EFFECTS.BuildTime + 0.1)
end

local function createHologramEffect(position, itemName)
    local hologram = Instance.new("Part")
    hologram.Size = Vector3.new(2, 2, 2)
    hologram.CFrame = CFrame.new(position)
    hologram.Anchored = true; hologram.CanCollide = false
    hologram.Material = Enum.Material.ForceField
    hologram.Color = EFFECTS.BeamColor
    hologram.Transparency = 0.7
    hologram.Parent = workspace

    TweenService:Create(hologram, TweenInfo.new(EFFECTS.BuildTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
        Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1)
    }):Play()

    TweenService:Create(hologram, TweenInfo.new(EFFECTS.BuildTime, Enum.EasingStyle.Linear), {
        Orientation = hologram.Orientation + Vector3.new(0, 360, 0)
    }):Play()

    Debris:AddItem(hologram, EFFECTS.BuildTime + 0.2)
end

local function createFloatingText(position, text)
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = EFFECTS.BeamColor
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.Parent = billboard

    local attachment = Instance.new("Attachment")
    attachment.WorldPosition = position
    attachment.Parent = workspace.Terrain
    billboard.Adornee = attachment
    billboard.Parent = workspace

    TweenService:Create(billboard, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = Vector3.new(0, 6, 0)
    }):Play()

    TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextTransparency = 1, TextStrokeTransparency = 1
    }):Play()

    task.delay(1.2, function()
        billboard:Destroy()
        attachment:Destroy()
    end)
end

local function playSound(soundId, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = volume or 0.5
    sound.Parent = workspace

    local conn
    conn = sound:GetPropertyChangedSignal("TimeLength"):Connect(function()
        if sound.TimeLength > 0 then
            sound:Play()
            task.delay(sound.TimeLength + 0.5, function()
                if sound and sound.Parent then sound:Destroy() end
            end)
            conn:Disconnect()
        end
    end)

    if sound.TimeLength > 0 then
        sound:Play()
        task.delay(sound.TimeLength + 0.5, function()
            if sound and sound.Parent then sound:Destroy() end
        end)
    end

    return sound
end

local function playBuildEffects(position, itemName, itemSize)
    itemSize = itemSize or Vector3.new(3, 3, 3)
    createBuildBeam(position)
    createGlowPart(position, itemSize)
    createParticleBurst(position + Vector3.new(0, itemSize.Y/2, 0))
    createHologramEffect(position, itemName)
    createFloatingText(position, "+ " .. itemName)
    playSound(EFFECTS.PlaceSound, 0.7)
end

--// ==========================================
--//  BLUEPRINT EXACT PLACEMENT
--// ==========================================

local function scanCurrentBase()
    local plot = getCurrentPlot()
    if not plot then return {} end
    local placedItems = plot:FindFirstChild("PlacedItems")
    if not placedItems then return {} end

    local existing = {}
    for _, item in ipairs(placedItems:GetChildren()) do
        if item:IsA("Model") then
            local name = item.Name
            local pos = item.WorldPivot and item.WorldPivot.Position or (item.PrimaryPart and item.PrimaryPart.Position)
            if pos then
                local key = name .. "_" .. math.round(pos.X) .. "_" .. math.round(pos.Z)
                existing[key] = true
            end
        end
    end
    return existing
end

local function getMissingItems()
    local plot = getCurrentPlot()
    if not plot then return {} end
    local bp = getBlueprintForPlot(plot)
    if not bp then return {} end
    
    local existing = scanCurrentBase()
    local missing = {}
    for _, blueprintItem in ipairs(bp) do
        local worldPos = blueprintItem.Position or (blueprintItem.WorldPivot and blueprintItem.WorldPivot.Position)
        if worldPos then
            local key = blueprintItem.Name .. "_" .. math.round(worldPos.X) .. "_" .. math.round(worldPos.Z)
            if not existing[key] then
                table.insert(missing, blueprintItem)
            end
        end
    end
    return missing
end

local function placeBlueprintItems(modeName, overrideItems)
    if isPlacing then return end
    isPlacing = true

    cachedPlayerPlot = nil
    cachedPlotRefreshTime = 0

    local plot = getCurrentPlot()
    if not plot then
        warn("[PLACE] No plot found! Stand inside a plot.")
        Library:Notify('Error | No plot detected. Walk into a plot first.', 3)
        isPlacing = false
        return
    end

    local itemsToPlace = overrideItems
    if not itemsToPlace then
        local bp = getBlueprintForPlot(plot)
        if not bp then
            Library:Notify('Error | No blueprint found for plot: ' .. plot.Name, 3)
            isPlacing = false
            return
        end
        itemsToPlace = bp
    end

    if #itemsToPlace == 0 then
        Library:Notify('Error | Blueprint is empty for plot: ' .. plot.Name, 3)
        isPlacing = false
        return
    end

    local bounds = getPlacementBounds(plot)
    if not bounds then
        warn("[PLACE] No placement bounds!")
        isPlacing = false
        return
    end

    print("\n╔══════════════════════════════════════╗")
    print("║     " .. string.format("%-33s", modeName) .. "║")
    print("║     Plot: " .. string.format("%-26s", plot.Name) .. "║")
    print("║     Items: " .. string.format("%-25d", #itemsToPlace) .. "║")
    print("╚══════════════════════════════════════╝\n")

    local placed = 0
    local failed = 0
    local startTime = tick()

    for i, item in ipairs(itemsToPlace) do
        local itemName = item.Name
        local worldPos = item.Position or (item.WorldPivot and item.WorldPivot.Position)

        if not worldPos then
            warn("[PLACE] No position for " .. itemName)
            failed = failed + 1
            continue
        end

        local relX, relZ = worldToRelative(worldPos, bounds)

        local itemRotation = 0
        if item.WorldPivot then
            local _, ry, _ = item.WorldPivot:ToEulerAnglesXYZ()
            local plotRotation = getPlotRotation(plot)
            itemRotation = ry - plotRotation
        elseif item.Attributes and item.Attributes._Yaw then
            itemRotation = math.rad(item.Attributes._Yaw)
        end

        local effectPos = relativeToWorld(relX, relZ, bounds)
        effectPos = Vector3.new(effectPos.X, bounds.topY + 2, effectPos.Z)

        playBuildEffects(effectPos, itemName, item.Size or Vector3.new(3,3,3))

        local success, err = pcall(function()
            PlaceItem:FireServer(itemName, relX, relZ, itemRotation)
        end)

        if success then
            placed = placed + 1
            print("[PLACE] " .. itemName .. " | rel(" .. string.format("%.2f", relX) .. ", " .. string.format("%.2f", relZ) .. ") | rot(" .. string.format("%.2f", itemRotation) .. ")")
        else
            failed = failed + 1
            warn("[PLACE] Failed: " .. tostring(err))
        end

        local progress = i / #itemsToPlace
        local barWidth = 30
        local filled = math.round(progress * barWidth)
        local bar = string.rep("█", filled) .. string.rep("░", barWidth - filled)
        local elapsed = tick() - startTime
        local eta = (elapsed / i) * (#itemsToPlace - i)

        print(string.format("[%s] %3d%% | %d/%d | %s | ETA: %.1fs", 
            bar, math.round(progress * 100), i, #itemsToPlace, itemName, eta))

        if i < #itemsToPlace then task.wait(PLACE_DELAY) end
    end

    playSound(EFFECTS.FinishSound, 1.0)

    print("\n╔══════════════════════════════════════╗")
    print("║     BUILD COMPLETE                   ║")
    print("║     Placed: " .. string.format("%-24d", placed) .. "║")
    print("║     Failed: " .. string.format("%-24d", failed) .. "║")
    print("║     Time: " .. string.format("%-26.1f", tick() - startTime) .. "s ║")
    print("╚══════════════════════════════════════╝\n")

    local effectPos = Vector3.new(bounds.centerX, bounds.topY + 10, bounds.centerZ)
    createFloatingText(effectPos, "✓ " .. modeName .. " COMPLETE!")
    isPlacing = false
end

--// ==========================================
--//  MAIN HEARTBEAT LOOP
--// ==========================================

RunService.Heartbeat:Connect(function()
    heartbeatCounter = heartbeatCounter + 1

    if Settings.AutobuyEnabled then
        smartAutoBuy()
    end

    if Settings.AutoplaceEnabled then
        placeRocketAuto()
    end

    if Settings.AutoplaceBuildings then
        placeBuildingAuto()
    end

    if Settings.LauncherEnabled then
        if #targetQueue == 0 and tick() - lastTargetScan >= 0.5 then
            lastTargetScan = tick()
            local targets = scanAllTargets()
            queueTargets(targets)
        end
        fireNextTarget()
    end
end)

--// ==========================================
--//  LINORIALIB COMPACT GUI
--// ==========================================

local Window = Library:CreateWindow({
    Title = 'Missile Wars | Blueprint',
    Center = true,
    AutoShow = true,
    TabPadding = 6,
    MenuFadeTime = 0.2,
    Size = UDim2.fromOffset(520, 380)
})

local Tabs = {
    Launcher = Window:AddTab('Launcher'),
    Blueprint = Window:AddTab('Build'),
    Autoplace = Window:AddTab('Place'),
    Autobuy = Window:AddTab('Buy'),
    Settings = Window:AddTab('Aim'),
    Server = Window:AddTab('Srv'),
    ['UI Settings'] = Window:AddTab('UI'),
}

--// LAUNCHER TAB
local LauncherLeft = Tabs.Launcher:AddLeftGroupbox('Launch')
LauncherLeft:AddToggle('EnableLauncher', {
    Text = 'Enable Launcher',
    Default = false,
    Callback = function(v) Settings.LauncherEnabled = v end
})
LauncherLeft:AddToggle('PrioritizeBigMeteor', {
    Text = 'Prioritize Meteor',
    Default = false,
    Callback = function(v) Settings.PrioritizeBigMeteor = v end
})
LauncherLeft:AddToggle('TargetPlayers', {
    Text = 'Target Players',
    Default = false,
    Callback = function(v) Settings.TargetPlayers = v end
})

local LauncherRight = Tabs.Launcher:AddRightGroupbox('Targets')
LauncherRight:AddDropdown('SelectBuildings', {
    Values = BUILD_TYPES,
    Default = BUILD_TYPES,
    Multi = true,
    Text = 'Buildings',
    Tooltip = 'Choose which buildings to target (includes Mansion)',
    Callback = function(sel)
        for _, name in ipairs(BUILD_TYPES) do Settings.TargetBuildings[name] = false end
        if sel and type(sel) == 'table' then
            for name, enabled in pairs(sel) do
                if enabled then Settings.TargetBuildings[name] = true end
            end
        else
            for _, name in ipairs(BUILD_TYPES) do Settings.TargetBuildings[name] = true end
        end
    end
})
LauncherRight:AddButton({
    Text = 'Reset Cache',
    Func = function()
        cachedPlacedItems = {}
        cachedPlacedItemsRefresh = 0
        cachedTargets = {}
        cachedTargetsRefresh = 0
        Library:Notify('Cache cleared', 2)
    end,
    DoubleClick = false
})

local LauncherSettings = Tabs.Launcher:AddLeftGroupbox('Settings')
LauncherSettings:AddSlider('FireDelay', {
    Text = 'Fire Delay',
    Default = 0.08,
    Min = 0.01,
    Max = 0.5,
    Rounding = 2,
    Compact = false,
    Callback = function(v) Settings.FireDelay = v end
})
LauncherSettings:AddSlider('FireBatchSize', {
    Text = 'Batch Size',
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Compact = false,
    Callback = function(v) Settings.FireBatch = v end
})
LauncherSettings:AddSlider('MaxTargetRange', {
    Text = 'Max Range',
    Default = 2000,
    Min = 100,
    Max = 5000,
    Rounding = 0,
    Compact = false,
    Callback = function(v) Settings.MaxTargetRange = v end
})
LauncherSettings:AddSlider('QueueMaxSize', {
    Text = 'Queue Limit',
    Default = 100,
    Min = 10,
    Max = 500,
    Rounding = 0,
    Compact = false,
    Callback = function(v) Settings.QueueMaxSize = v end
})

local LauncherStats = Tabs.Launcher:AddRightGroupbox('Live Stats')
launcherStatsLabel = LauncherStats:AddLabel('Queue: 0 | Cached: 0')
LauncherStats:AddButton({
    Text = 'Clear Queue',
    Func = function()
        targetQueue = {}
        cachedTargets = {}
        cachedTargetsRefresh = 0
        Library:Notify('Target queue cleared', 2)
    end,
    DoubleClick = false
})

--// BLUEPRINT TAB
local BlueprintLeft = Tabs.Blueprint:AddLeftGroupbox('Blueprint')
blueprintStatusLabel = BlueprintLeft:AddLabel('Items: GitHub Mode')
blueprintRocketsLabel = BlueprintLeft:AddLabel('Rockets: Auto-detect')
blueprintBuildingsLabel = BlueprintLeft:AddLabel('Buildings: Auto-detect')

local BlueprintRight = Tabs.Blueprint:AddRightGroupbox('Actions')
BlueprintRight:AddButton({
    Text = 'NEW BUILD',
    Func = function()
        if isPlacing then
            Library:Notify('Wait | Already placing...', 2)
            return
        end
        task.spawn(function()
            placeBlueprintItems('NEW BUILD')
        end)
    end,
    DoubleClick = false
})
BlueprintRight:AddButton({
    Text = 'REPAIR',
    Func = function()
        if isPlacing then
            Library:Notify('Wait | Already placing...', 2)
            return
        end
        local plot = getCurrentPlot()
        if not plot then
            Library:Notify('Error | No plot detected!', 3)
            return
        end
        local bp = getBlueprintForPlot(plot)
        if not bp then
            Library:Notify('Error | No blueprint for plot: ' .. plot.Name, 3)
            return
        end
        local missing = getMissingItems()
        if #missing == 0 then
            Library:Notify('Complete | Base is already complete!', 3)
            return
        end
        Library:Notify('Missing: ' .. #missing .. ' items', 2)
        task.spawn(function()
            placeBlueprintItems('REPAIR MODE', missing)
        end)
    end,
    DoubleClick = false
})
BlueprintRight:AddButton({
    Text = 'Reset Queues',
    Func = function()
        local plot = getCurrentPlot()
        local _, needs = getBlueprintForPlot(plot)
        rebuildBuyQueues(needs)
        Library:Notify('Queues rebuilt for ' .. (plot and plot.Name or "unknown"), 2)
    end,
    DoubleClick = false
})

--// AUTOPLACE TAB
local AutoplaceLeft = Tabs.Autoplace:AddLeftGroupbox('Missiles')
AutoplaceLeft:AddToggle('EnableMissileAutoplace', {
    Text = 'Enable Missiles',
    Default = false,
    Callback = function(v) Settings.AutoplaceEnabled = v end
})
AutoplaceLeft:AddDropdown('SelectRocketsAutoplace', {
    Values = ROCKET_NAMES,
    Default = ROCKET_NAMES,
    Multi = true,
    Text = 'Rockets',
    Tooltip = 'Choose rockets for autoplace',
    Callback = function(sel)
        for _, name in ipairs(ROCKET_NAMES) do Settings.AutoplaceRockets[name] = false end
        if sel and type(sel) == 'table' then
            for name, enabled in pairs(sel) do
                if enabled then Settings.AutoplaceRockets[name] = true end
            end
        else
            for _, name in ipairs(ROCKET_NAMES) do Settings.AutoplaceRockets[name] = true end
        end
    end
})

local AutoplaceRight = Tabs.Autoplace:AddRightGroupbox('Buildings')
AutoplaceRight:AddToggle('EnableBuildingAutoplace', {
    Text = 'Enable Buildings',
    Default = false,
    Callback = function(v) Settings.AutoplaceBuildings = v end
})
AutoplaceRight:AddDropdown('SelectBuildingsAutoplace', {
    Values = BUILD_TYPES,
    Default = BUILD_TYPES,
    Multi = true,
    Text = 'Buildings',
    Tooltip = 'Choose buildings for autoplace (includes Mansion)',
    Callback = function(sel)
        for _, name in ipairs(BUILD_TYPES) do Settings.AutoplaceBuildingsList[name] = false end
        if sel and type(sel) == 'table' then
            for name, enabled in pairs(sel) do
                if enabled then Settings.AutoplaceBuildingsList[name] = true end
            end
        else
            for _, name in ipairs(BUILD_TYPES) do Settings.AutoplaceBuildingsList[name] = true end
        end
    end
})

local AutoplaceSettings = Tabs.Autoplace:AddLeftGroupbox('Timing')
AutoplaceSettings:AddSlider('MissilePlaceDelay', {
    Text = 'Missile Delay',
    Default = 0.15,
    Min = 0.05,
    Max = 1,
    Rounding = 2,
    Compact = false,
    Callback = function(v) Settings.PlaceDelay = v end
})
AutoplaceSettings:AddSlider('BuildingPlaceDelay', {
    Text = 'Building Delay',
    Default = 0.3,
    Min = 0.05,
    Max = 1,
    Rounding = 2,
    Compact = false,
    Callback = function(v) Settings.BuildingPlaceDelay = v end
})
AutoplaceSettings:AddSlider('EdgeAvoidance', {
    Text = 'Edge Avoid',
    Default = 3,
    Min = 0,
    Max = 10,
    Rounding = 1,
    Compact = false,
    Callback = function(v) Settings.EdgeAvoidance = v end
})

--// AUTOBUY TAB
local AutobuyLeft = Tabs.Autobuy:AddLeftGroupbox('Master')
AutobuyLeft:AddToggle('EnableAutobuy', {
    Text = 'Enable Autobuy',
    Default = false,
    Callback = function(v) Settings.AutobuyEnabled = v end
})

local AutobuyRockets = Tabs.Autobuy:AddLeftGroupbox('Rockets')
AutobuyRockets:AddToggle('AutobuyRockets', {
    Text = 'Buy Rockets',
    Default = false,
    Callback = function(v)
        Settings.AutobuyRockets = v
        if v then lastRocketBuy = 0 end
    end
})
AutobuyRockets:AddDropdown('SelectRocketsAutobuy', {
    Values = ROCKET_NAMES,
    Default = ROCKET_NAMES,
    Multi = true,
    Text = 'Rockets',
    Tooltip = 'Choose rockets to autobuy',
    Callback = function(sel)
        for _, name in ipairs(ROCKET_NAMES) do Settings.AutobuyRocketsList[name] = false end
        if sel and type(sel) == 'table' then
            for name, enabled in pairs(sel) do
                if enabled then Settings.AutobuyRocketsList[name] = true end
            end
        else
            for _, name in ipairs(ROCKET_NAMES) do Settings.AutobuyRocketsList[name] = true end
        end
    end
})

local AutobuyBuildings = Tabs.Autobuy:AddRightGroupbox('Buildings')
AutobuyBuildings:AddToggle('AutobuyBuildings', {
    Text = 'Buy Buildings',
    Default = false,
    Callback = function(v)
        Settings.AutobuyBuildings = v
        if v then lastBuildingBuy = 0 end
    end
})
AutobuyBuildings:AddDropdown('AutobuyBuildingType', {
    Values = BUILD_TYPES,
    Default = 1,
    Multi = false,
    Text = 'Type',
    Tooltip = 'Single building type to autobuy',
    Callback = function(v) Settings.AutobuyBuilding = v end
})

local AutobuyWorkers = Tabs.Autobuy:AddRightGroupbox('Workers')
AutobuyWorkers:AddToggle('AutobuyWorkers', {
    Text = 'Buy Workers',
    Default = false,
    Callback = function(v)
        Settings.AutobuyWorkers = v
        if v then lastWorkerBuy = 0 end
    end
})
AutobuyWorkers:AddDropdown('SelectWorkersAutobuy', {
    Values = WORKER_NAMES,
    Default = WORKER_NAMES,
    Multi = true,
    Text = 'Workers',
    Tooltip = 'Choose workers to autobuy',
    Callback = function(sel)
        for _, name in ipairs(WORKER_NAMES) do Settings.AutobuyWorkersList[name] = false end
        if sel and type(sel) == 'table' then
            for name, enabled in pairs(sel) do
                if enabled then Settings.AutobuyWorkersList[name] = true end
            end
        else
            for _, name in ipairs(WORKER_NAMES) do Settings.AutobuyWorkersList[name] = true end
        end
    end
})

local AutobuySettings = Tabs.Autobuy:AddLeftGroupbox('Delay')
AutobuySettings:AddSlider('BuyDelay', {
    Text = 'Buy Delay',
    Default = 0.01,
    Min = 0.01,
    Max = 1,
    Rounding = 2,
    Compact = false,
    Callback = function(v) Settings.BuyDelay = v end
})

--// SETTINGS TAB
local SettingsLeft = Tabs.Settings:AddLeftGroupbox('Launch')
SettingsLeft:AddSlider('FireDelay', {
    Text = 'Fire Delay',
    Default = 0.08,
    Min = 0.01,
    Max = 0.5,
    Rounding = 2,
    Compact = false,
    Callback = function(v) Settings.FireDelay = v end
})
SettingsLeft:AddSlider('FireBatchSize', {
    Text = 'Batch Size',
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Compact = false,
    Callback = function(v) Settings.FireBatch = v end
})

local SettingsRight = Tabs.Settings:AddRightGroupbox('Stats')
SettingsRight:AddLabel('Success: 0 | Fail: 0')
SettingsRight:AddButton({
    Text = 'Reset Stats',
    Func = function()
        PlacementStats.successCount = 0
        PlacementStats.failCount = 0
        Library:Notify('Stats cleared', 2)
    end,
    DoubleClick = false
})

--// SERVER TAB
local ServerLeft = Tabs.Server:AddLeftGroupbox('Server')
ServerLeft:AddButton({
    Text = 'Rejoin',
    Func = function()
        local success = pcall(rejoinServer)
        Library:Notify(success and 'Rejoining...' or 'Error', 2)
    end,
    DoubleClick = false
})
ServerLeft:AddButton({
    Text = 'New Server',
    Func = function()
        local success = pcall(newServer)
        Library:Notify(success and 'Switching...' or 'Error', 2)
    end,
    DoubleClick = false
})
ServerLeft:AddButton({
    Text = '5-6 Players',
    Func = function()
        local success = pcall(joinServerWith56Players)
        Library:Notify(success and 'Switching...' or 'Error', 2)
    end,
    DoubleClick = false
})

local ServerRight = Tabs.Server:AddRightGroupbox('UI')
ServerRight:AddButton({
    Text = 'Close & Disable',
    Func = function()
        disableAllToggles()
        Library:Unload()
    end,
    DoubleClick = false
})

--// UI SETTINGS TAB (Theme & Save Manager)
local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')
MenuGroup:AddButton({
    Text = 'Unload',
    Func = function() Library:Unload() end,
    DoubleClick = false
})
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', {
    Default = 'End',
    NoUI = true,
    Text = 'Menu keybind'
})
Library.ToggleKeybind = Options.MenuKeybind

--// THEME & SAVE MANAGERS
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('MissileWarsBlueprint')
SaveManager:SetFolder('MissileWarsBlueprint/specific-game')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])

--// WATERMARK
Library:SetWatermarkVisibility(true)
local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60
local WatermarkConnection = game:GetService('RunService').RenderStepped:Connect(function()
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter
        FrameTimer = tick()
        FrameCounter = 0
    end
    Library:SetWatermark(('Missile Wars | %s fps | %s ms'):format(
        math.floor(FPS),
        math.floor(game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue())
    ))
end)

Library:OnUnload(function()
    WatermarkConnection:Disconnect()
    Library.Unloaded = true
end)

--// INIT NOTIFICATION
Library:Notify('Blueprint v6 Loaded | GitHub Mode | 6 Plots Linked', 3)

print("\n[✓] Blueprint Builder v6 (LinoriaLib Compact) loaded!")
print("    GitHub Mode: 6 plot blueprints auto-loaded from URLs")
print("    Compact UI: 520x340 rectangle")
print("    Multi-plot: Build/Repair works on ANY plot you're inside")
print("    Detection: Position bounds + Raycast + Closest + Owned fallback")
print("    Tabs: Launcher | Build | Place | Buy | Aim | Srv | UI")
