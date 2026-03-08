-- tesdebug.lua — Dump EquippedItems + Inventory subtables to find rod storage
local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LP      = Players.LocalPlayer
local LOG_FILE = "debug_rod2_" .. LP.Name .. ".txt"

local lines = {}
local function log(msg) print(msg) table.insert(lines, tostring(msg)) end
local function flush()
    pcall(function() writefile(LOG_FILE, table.concat(lines, "\n")) end)
    print("[LOG] Saved → " .. LOG_FILE)
end
local function dumpTable(tbl, prefix, depth, maxDepth)
    prefix = prefix or "" ; depth = depth or 0 ; maxDepth = maxDepth or 4
    if depth > maxDepth then log(prefix .. "...(max depth)") return end
    if type(tbl) ~= "table" then log(prefix .. " = " .. tostring(tbl)) return end
    for k, v in pairs(tbl) do
        local key = prefix .. tostring(k)
        if type(v) == "table" then
            log(key .. " = {") ; dumpTable(v, key .. ".", depth+1, maxDepth) ; log("}")
        else log(key .. " = " .. tostring(v)) end
    end
end

local Replion = require(RS.Packages.Replion)
local DataReplion = Replion.Client:WaitReplion("Data")

local equippedId = DataReplion:Get({"EquippedId"})
log("EquippedId = " .. tostring(equippedId))
log("")

-- 1. Dump EquippedItems table
log("─── EquippedItems ───")
local ok1, ei = pcall(function() return DataReplion:Get({"EquippedItems"}) or {} end)
if ok1 then dumpTable(ei, "  EquippedItems.", 0, 4)
else log("  [ERR] " .. tostring(ei)) end
log("")

-- 2. Dump all sub-keys of Inventory to find rods
log("─── Inventory sub-keys ───")
local ok2, inv = pcall(function() return DataReplion:Get({"Inventory"}) or {} end)
if ok2 then
    for k, v in pairs(inv) do
        log(type(v) == "table" and ("  [TABLE] Inventory." .. k) or ("  Inventory." .. k .. " = " .. tostring(v)))
    end
else log("  [ERR] " .. tostring(inv)) end
log("")

-- 3. Search every Inventory sub-table for the EquippedId UUID
log("─── UUID search in all Inventory tables ───")
if ok2 and equippedId then
    for subKey, subTable in pairs(inv) do
        if type(subTable) == "table" then
            for _, item in ipairs(subTable) do
                if type(item) == "table" and tostring(item.UUID) == tostring(equippedId) then
                    log("  ✅ FOUND in Inventory." .. subKey .. ":")
                    dumpTable(item, "    ", 0, 3)
                end
            end
        end
    end
end

-- 4. Also try ItemUtility on EquippedItems entries
log("")
log("─── ItemUtility on EquippedItems ───")
local ItemUtility = require(RS.Shared.ItemUtility)
if ok1 and type(ei) == "table" then
    for k, v in pairs(ei) do
        if type(v) == "table" and v.Id then
            local okI, data = pcall(function() return ItemUtility:GetItemData(v.Id) end)
            if okI and data and data.Data then
                log(string.format("  [%s] Id=%s Name=%s Type=%s", k, tostring(v.Id), tostring(data.Data.Name), tostring(data.Data.Type)))
            else
                log(string.format("  [%s] Id=%s (GetItemData failed)", k, tostring(v.Id)))
            end
        elseif type(v) ~= "table" then
            log(string.format("  [%s] = %s", k, tostring(v)))
        end
    end
end

log("\n=== DONE ===")
flush()
