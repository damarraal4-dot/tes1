-- ═══════════════════════════════════════════════════════════════════
--  autotrade.lua
--  Inventory tracker → sends data to aggregation server
--  Jalankan di auto-exec Delta
-- ═══════════════════════════════════════════════════════════════════

local RS          = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local Replion     = require(RS.Packages.Replion)

-- ===== SETTING =====
local SERVER_URL  = "https://dashboard.amer.web.id/report" -- Ganti IP jika server di VPS/HP lain
local INTERVAL    = 30   -- cek setiap berapa detik
-- ===================

local DataReplion = Replion.Client:WaitReplion("Data")
local LP          = Players.LocalPlayer
local HWID        = tostring((gethwid or function() return "unknown" end)()):sub(1, 16)

-- ===== HITUNG INVENTORY =====
local function getInventory()
    local ItemUtility = require(RS.Shared.ItemUtility)

    local evo         = 0
    local secretTotal = 0
    local rubyGem     = 0   -- Tier 5, name=Ruby, VariantId=Gemstone
    local secretFish  = {}  -- { [name] = { qty=n, variant="..." } } for Tier 7

    for _, item in ipairs(DataReplion:Get({"Inventory", "Items"}) or {}) do
        local ok, data = pcall(function() return ItemUtility:GetItemData(item.Id) end)
        if ok and data and data.Data then
            local name      = tostring(data.Data.Name)
            local qty       = item.Quantity or 1
            local itemType  = tostring(data.Data.Type or "")
            local itemTier  = data.Data.Tier
            local variantId = tostring((item.Metadata and item.Metadata.VariantId) or "")
            local matched   = false

            -- Tier 7 (Secret) fish — group by name+variant so
            -- "Ancient Lochness Monster [Galaxy]" and plain ones stay separate
            if itemType == "Fish" and itemTier == 7 then
                local key = name .. "|" .. variantId   -- e.g. "Ancient Lochness Monster|Galaxy"
                if not secretFish[key] then
                    secretFish[key] = { name = name, qty = 0, variant = variantId }
                end
                secretFish[key].qty += qty
                matched = true

            -- Tier 5 Ruby with Gemstone variant
            elseif itemTier == 5 and name == "Ruby" and variantId == "Gemstone" then
                rubyGem += qty
                matched = true

            -- EVO stones
            elseif name == "Evolved Enchant Stone" then
                evo += qty
                matched = true
            end

            if not matched then
                secretTotal += qty
            end
        end
    end

    -- Convert secretFish map to list for JSON serialization
    local secretList = {}
    for fishName, info in pairs(secretFish) do
        table.insert(secretList, {
            name    = fishName,
            qty     = info.qty,
            variant = info.variant
        })
    end
    table.sort(secretList, function(a, b) return a.qty > b.qty end)

    return evo, secretList, rubyGem, secretTotal
end

-- ===== GET PLAYER STATISTICS =====
local function getStatistics()
    local ok, stats = pcall(function()
        return DataReplion:Get({"Statistics"}) or {}
    end)
    if not ok then return {} end
    return {
        fishCaught        = stats.FishCaught        or 0,
        monthlyFishCaught = stats.MonthlyFishCaught or 0,
        caughtSecrets     = stats.CaughtSecrets     or 0,
        rarestFish        = stats.RarestFishCaught  or 0,
        monthlyLevel      = stats.MonthlyLevel      or 0,
    }
end

-- ===== POST ke Server Aggregator =====
local function postToServer(evo, secretList, rubyGem, secretTotal)
    local serverId = tostring(game.JobId):sub(1, 8)
    local stats    = getStatistics()
    local ok, result = pcall(function()
        return request({
            Url     = SERVER_URL,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = HttpService:JSONEncode({
                player      = LP.Name,
                hwid        = HWID,
                serverId    = serverId,
                evo         = evo,
                secrets     = secretList,
                ruby_gem    = rubyGem,
                secretTotal = secretTotal,
                stats       = stats,  -- { fishCaught, monthlyFishCaught, caughtSecrets, ... }
            })
        })
    end)
    if ok and result and result.StatusCode == 200 then
        print(string.format("[Inv] ✅ Sent | EVO=%d | T7=%d | Ruby=%d",
            evo, #secretList, rubyGem))
    else
        warn("[Inv] ❌ Server error:", tostring(result and result.StatusCode or result))
    end
end

-- ===== MAIN LOOP =====
print(string.format("[InvChecker] Start | Akun: %s | Interval: %ds", LP.Name, INTERVAL))
postToServer(getInventory())
while true do
    task.wait(INTERVAL)
    postToServer(getInventory())
end