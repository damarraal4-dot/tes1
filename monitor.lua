-- ═══════════════════════════════════════════════════════════════════
--  monitor.lua — Native Roblox port of AccountFetcher/monitor.py
--
--  Reads all stats directly from the game (no external API needed):
--    • FishCaught, FPM, FPH (delta between reports)
--    • EVO stones & SCTB target items
--    • Equipped rod
--    • Deep Sea Quest status & remaining objectives
--    • Secret fish (Tier 7) with variant
--    • Online status (running this script = online)
--
--  Sends a combined embed to SERVER_URL every INTERVAL seconds.
--  Drop this into auto-exec alongside autotrade.lua — they each
--  report independently, server.py aggregates.
-- ═══════════════════════════════════════════════════════════════════

local RS          = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local Replion     = require(RS.Packages.Replion)

-- ===== SETTINGS =====
local SERVER_URL  = "https://dashboard.amer.web.id/report"
local INTERVAL    = 30   -- seconds between reports
-- ====================

local DataReplion = Replion.Client:WaitReplion("Data")
local LP          = Players.LocalPlayer
local HWID        = tostring((gethwid or function() return "unknown" end)()):sub(1, 16)
local serverId    = tostring(game.JobId):sub(1, 8)

-- ── TARGET_ITEMS mirror of config.py ──────────────────────────────
-- These are the SCTB (Sacred/Chaotic Tier B) tracked items
-- SC Tumbal whitelist — tracked by name regardless of tier
local TARGET_NAMES = {
    -- Tier 6 (Mythic)
    ["King Jelly"]        = true,
    ["Mosasaur Shark"]    = true,
    ["Elshark Gran Maja"] = true,
    ["Gladiator Shark"]   = true,
    ["Robot Kraken"]      = true,
    ["Giant Squid"]       = true,
    ["Panther Eel"]       = true,
    ["Cryoshade Glider"]  = true,
    -- Tier 7 (Secret)
    ["Blob Shark"]        = true,
    ["Bone Whale"]        = true,
    ["Great Whale"]       = true,
    ["Depthseeker Ray"]   = true,
    ["King Crab"]         = true,
    ["Queen Crab"]        = true,
}

-- Quest objective labels (index 0-based like Python, stored 1-based in Lua)
local OBJ_NAMES = { "300 Rare", "3 Mythic", "1 Secret", "1M Coin" }

-- ── FPM/FPH tracking ──────────────────────────────────────────────
local prevFishCaught = nil
local prevCheckTime  = nil

-- ═══════════════════════════════════════════════════════════════════
local function getInventoryStats()
    local ItemUtility = require(RS.Shared.ItemUtility)

    local evo         = 0
    local sctb        = 0
    local secretFish  = {}   -- { key = {name, qty, variant} }
    local rubyGem     = 0

    for _, item in ipairs(DataReplion:Get({"Inventory", "Items"}) or {}) do
        local ok, data = pcall(function() return ItemUtility:GetItemData(item.Id) end)
        if ok and data and data.Data then
            local name      = tostring(data.Data.Name)
            local qty       = item.Quantity or 1
            local itemType  = tostring(data.Data.Type or "")
            local itemTier  = data.Data.Tier
            local variantId = tostring((item.Metadata and item.Metadata.VariantId) or "")

            -- EVO stones
            if name == "Evolved Enchant Stone" then
                evo += qty

            -- SCTB target items (by name)
            elseif TARGET_NAMES[name] then
                sctb += qty

            -- Tier 7 secret fish (grouped by name+variant)
            elseif itemType == "Fish" and itemTier == 7 then
                local key = name .. "|" .. variantId
                if not secretFish[key] then
                    secretFish[key] = { name = name, qty = 0, variant = variantId }
                end
                secretFish[key].qty += qty

            -- Ruby Gemstone (Tier 5)
            elseif itemTier == 5 and name == "Ruby" and variantId == "Gemstone" then
                rubyGem += qty
            end
        end
    end

    -- Convert secretFish to list sorted by qty
    local secretList = {}
    for _, info in pairs(secretFish) do
        table.insert(secretList, info)
    end
    table.sort(secretList, function(a, b) return a.qty > b.qty end)

    return evo, sctb, rubyGem, secretList
end

-- ═══════════════════════════════════════════════════════════════════
local function getStatistics()
    local ok, stats = pcall(function()
        return DataReplion:Get({"Statistics"}) or {}
    end)
    if not ok then return 0, 0, 0, 0, 0 end
    return
        stats.FishCaught        or 0,
        stats.MonthlyFishCaught or 0,
        stats.CaughtSecrets     or 0,
        stats.RarestFishCaught  or 0,
        stats.MonthlyLevel      or 0
end

-- ═══════════════════════════════════════════════════════════════════
local function getEquippedRod()
    -- EquippedId (UUID) and EquippedType live at the root level
    local okE, equippedId = pcall(function()
        return DataReplion:Get({"EquippedId"})
    end)
    local okT, equippedType = pcall(function()
        return DataReplion:Get({"EquippedType"})
    end)

    if not okE or not equippedId then return "Unknown" end
    if equippedType ~= "Fishing Rods" then return tostring(equippedType or "Unknown") end

    -- Match the UUID against Inventory.Fishing Rods to get the rod name
    local ItemUtility = require(RS.Shared.ItemUtility)
    for _, item in ipairs(DataReplion:Get({"Inventory", "Fishing Rods"}) or {}) do
        if tostring(item.UUID) == tostring(equippedId) then
            local okI, data = pcall(function() return ItemUtility:GetItemData(item.Id) end)
            if okI and data and data.Data then
                return tostring(data.Data.Name)
            end
            break
        end
    end

    -- Fallback: return short UUID
    return "Rod:" .. tostring(equippedId):sub(1, 8)
end

-- ═══════════════════════════════════════════════════════════════════
local function getQuestInfo()
    -- Only report quests related to GhostFinn (name contains "ghost")
    local ok, quests = pcall(function()
        return DataReplion:Get({"Quests"}) or {}
    end)
    if not ok then return false, {} end

    local mainline = quests.Mainline or {}
    local activeQuests = {}

    for questName, qData in pairs(mainline) do
        -- Filter: only GhostFinn quests
        if type(qData) == "table" and questName:lower():find("ghost") then
            local currentObj = qData.CurrentObj or 1
            local objectives = qData.Objectives or {}
            local totalObj   = 0
            for _ in pairs(objectives) do totalObj += 1 end
            -- Show current objective progress value
            local curObjData = objectives[currentObj] or {}
            local progress   = curObjData.Progress or 0
            table.insert(activeQuests, string.format(
                "%s — obj %d/%d (progress: %d)",
                questName, currentObj, totalObj, progress
            ))
        end
    end

    local active = #activeQuests > 0
    return active, activeQuests
end


-- ═══════════════════════════════════════════════════════════════════
local function calcFPM(fishNow)
    local fpm = 0.0
    local fph = 0.0
    local now = tick()

    if prevFishCaught ~= nil and prevCheckTime ~= nil then
        local elapsedMin = (now - prevCheckTime) / 60
        if elapsedMin > 0 then
            local delta = fishNow - prevFishCaught
            if delta >= 0 then
                fpm = delta / elapsedMin
                fph = fpm * 60
            end
        end
    end

    prevFishCaught = fishNow
    prevCheckTime  = now

    return math.floor(fpm * 100) / 100, math.floor(fph)
end

-- ═══════════════════════════════════════════════════════════════════
local function buildAndSend()
    -- Gather all data
    local evo, sctb, rubyGem, secretList = getInventoryStats()
    local fishCaught, monthlyFish, caughtSecrets, rarestFish, monthlyLv = getStatistics()
    local fpm, fph = calcFPM(fishCaught)
    local rodName = getEquippedRod()
    local questActive, questRemaining = getQuestInfo()

    -- Quest label
    local questStr = "No Quest"
    if questActive then
        if #questRemaining > 0 then
            questStr = "Active — sisa " .. table.concat(questRemaining, ", ")
        else
            questStr = "Active — all done ✅"
        end
    end

    local httpFn = request or (syn and syn.request) or (http and http.request) or http_request

    if not httpFn then
        warn("[Monitor] No HTTP function available")
        return
    end

    local ok, result = pcall(function()
        return httpFn({
            Url     = SERVER_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = HttpService:JSONEncode({
                -- Identity
                player   = LP.Name,
                hwid     = HWID,
                serverId = serverId,

                -- Inventory
                evo      = evo,
                sctb     = sctb,                -- SCTB target item count
                ruby_gem = rubyGem,
                secrets  = secretList,          -- Tier 7 fish list

                -- Statistics
                stats = {
                    fishCaught        = fishCaught,
                    monthlyFishCaught = monthlyFish,
                    caughtSecrets     = caughtSecrets,
                    rarestFish        = rarestFish,
                    monthlyLevel      = monthlyLv,
                    fpm               = fpm,
                    fph               = fph,
                },

                -- Rod & Quest
                rod   = rodName,
                quest = {
                    active    = questActive,
                    remaining = questRemaining,
                    label     = questStr,
                },
            })
        })
    end)

    if ok and result and result.StatusCode == 200 then
        print(string.format(
            "[Monitor] ✅ %s | Fish=%d | FPM=%.2f | EVO=%d | SCTB=%d | Rod=%s | Quest=%s",
            LP.Name, fishCaught, fpm, evo, sctb, rodName, questStr
        ))
    else
        warn("[Monitor] ❌ Error:", tostring(result and result.StatusCode or result))
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  Main loop
-- ═══════════════════════════════════════════════════════════════════
print(string.format("[Monitor] Start | %s | Interval: %ds", LP.Name, INTERVAL))
buildAndSend()
while true do
    task.wait(INTERVAL)
    buildAndSend()
end
