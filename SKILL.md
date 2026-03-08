---
name: fisch-roblox-fleet-tracker
description: >
  Knowledge for building a Roblox Fisch game fleet tracker using DataReplion,
  a Python aggregation server, Discord webhook, and a web dashboard. Covers
  exact DataReplion paths, inventory structure, and system architecture.
---

# Fisch Game — Fleet Tracker Skill

## Overview

This skill documents how to build a multi-account fleet tracking system for the
Roblox game **Fisch**. A Lua executor script (Delta) runs in each Roblox
instance, reads live player data directly from `DataReplion`, and POSTs it to
a Python Flask aggregation server. The server groups data by game server,
calculates performance metrics, and exposes a Discord webhook embed and a
web dashboard.

---

## Architecture

```
[Roblox Instance 1]  ─┐
[Roblox Instance 2]  ─┼──POST /report──► [Python Flask Server]
[Roblox Instance N]  ─┘                        │
                                        ┌───────┴────────┐
                                   Discord embed     Web dashboard
                                   (webhook)         (/:5000)
```

---

## Lua — DataReplion Setup

```lua
local RS      = game:GetService("ReplicatedStorage")
local Replion = require(RS.Packages.Replion)
local DataReplion = Replion.Client:WaitReplion("Data")
```

---

## Confirmed DataReplion Paths (Fisch)

All paths are passed as a table to `DataReplion:Get({...})`.

### Statistics
| Path | Key | Type | Notes |
|---|---|---|---|
| `{"Statistics"}` | `FishCaught` | number | All-time total fish caught |
| `{"Statistics"}` | `MonthlyFishCaught` | number | This month |
| `{"Statistics"}` | `CaughtSecrets` | number | Total secrets ever caught |
| `{"Statistics"}` | `RarestFishCaught` | number | Probability of rarest catch |
| `{"Statistics"}` | `MonthlyLevel` | number | Monthly rank level |
| `{"Statistics"}` | `Throws` | number | Total throws |

### Inventory

Inventory uses **separate sub-tables per item type**, NOT one flat array.

```lua
-- Correct paths:
DataReplion:Get({"Inventory", "Items"})         -- Fish & consumables
DataReplion:Get({"Inventory", "Fishing Rods"})  -- Rods (use for equipped rod lookup)
DataReplion:Get({"Inventory", "Baits"})
DataReplion:Get({"Inventory", "Potions"})
DataReplion:Get({"Inventory", "Lanterns"})
DataReplion:Get({"Inventory", "Charms"})
DataReplion:Get({"Inventory", "Halos"})
DataReplion:Get({"Inventory", "Emotes"})
DataReplion:Get({"Inventory", "Boats"})
DataReplion:Get({"Inventory", "Totems"})
```

Each item slot looks like:
```lua
{
  Id       = 345,          -- numeric item ID, pass to ItemUtility:GetItemData(id)
  UUID     = "bebf17bd-...",
  Favorited = false,
  Metadata = {
    VariantId = "Galaxy",  -- variant/mutation name (string), nil if none
    VariantSeed = 1768752600,
    Weight = 358790.6,
    OriginalOwner = 10071308031,
    LT = 1768831277,
  }
}
```

### Getting Item Data

```lua
local ItemUtility = require(RS.Shared.ItemUtility)
local data = ItemUtility:GetItemData(item.Id)
-- data.Data.Name    → item name string
-- data.Data.Type    → "Fish", "Enchant Stone", etc.
-- data.Data.Tier    → 1-7 (7 = Secret)
-- data.Data.Id      → same as item.Id
-- data.SellPrice
-- data.Weight.Default
```

### Equipped Items

```lua
-- Root-level keys (NOT nested under Player):
DataReplion:Get({"EquippedId"})    -- UUID string of currently equipped item
DataReplion:Get({"EquippedType"})  -- "Fishing Rods", "Baits", etc.

-- EquippedItems = array of UUIDs for ALL equipped slots
DataReplion:Get({"EquippedItems"}) -- { "uuid1", "uuid2", ... }

-- To get rod NAME:
-- 1. Read EquippedId
-- 2. Scan Inventory["Fishing Rods"] for matching UUID
-- 3. Call ItemUtility:GetItemData(item.Id).Data.Name
```

### Quests

```lua
-- Structure (NOT Active/Completed booleans — uses Progress):
DataReplion:Get({"Quests"}) 
-- Returns:
-- {
--   Mainline = {
--     ["Frog Army"] = {
--       CurrentObj = 1,
--       Timestamp  = 1767541546,
--       LimitedEventQuest = false,
--       Objectives = {
--         { Progress = 1, Id = 1 },
--         { Progress = 0, Id = 2 },
--       }
--     },
--     ...
--   },
--   Event = { ... }
-- }
-- A quest exists in Mainline if it's active/in-progress.
-- "Completed" quests move to CompletedQuests table.
```

### Other Useful Root-Level Keys

```lua
DataReplion:Get({"Coins"})           -- player's coin balance
DataReplion:Get({"Level"})           -- player level
DataReplion:Get({"XP"})
DataReplion:Get({"Tix"})             -- premium currency
DataReplion:Get({"Doubloons"})
DataReplion:Get({"EquippedBaitId"})  -- numeric bait ID
DataReplion:Get({"EquippedCharmId"})
DataReplion:Get({"AutoFishing"})     -- boolean
DataReplion:Get({"AutoFishingUsed"}) -- boolean
DataReplion:Get({"LastBoatId"})
DataReplion:Get({"SavedLocation"})   -- "Fisherman Island", etc.
```

### SCTB Target Item Names (config.py)

These are the SC Tumbal fish tracked by name (regardless of tier):
```lua
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
```

---

## HTTP from Lua (Executor)

```lua
-- Works with Delta executor:
local httpFn = request or (syn and syn.request) or (http and http.request) or http_request
httpFn({
    Url     = "https://...",
    Method  = "POST",
    Headers = {["Content-Type"] = "application/json"},
    Body    = HttpService:JSONEncode(payload),
})
-- result.StatusCode == 200 means success
```

---

## Python Server — Key Payload Schema

The Lua script POSTs this JSON to `/report`:

```json
{
  "player":      "PlayerName",
  "hwid":        "4cbcec83...",
  "serverId":    "a1b2c3d4",
  "evo":         16,
  "sctb":        0,
  "ruby_gem":    0,
  "secrets":     [{"name": "Ancient Lochness Monster", "qty": 15, "variant": ""},
                  {"name": "Ancient Lochness Monster", "qty": 1, "variant": "Galaxy"}],
  "stats": {
    "fishCaught":        2115014,
    "monthlyFishCaught": 8296,
    "caughtSecrets":     1,
    "rarestFish":        2.5e-07,
    "monthlyLevel":      3,
    "fpm":               9.64,
    "fph":               578
  },
  "rod":   "GhostFinn Rod",
  "quest": {
    "active":    true,
    "remaining": [],
    "label":     "Active — Frog Army (1/2), Diamond Researcher (1/6)"
  }
}
```

---

## Fish/Minute Calculation Pattern

```python
# Server-side: track delta between consecutive reports
prev_fish = {}   # { player: {fish, ts} }

fish_now = stats.get('fishCaught', 0)
if player in prev_fish:
    elapsed_min = (now - prev_fish[player]['ts']) / 60.0
    delta = fish_now - prev_fish[player]['fish']
    fpm = round(max(delta, 0) / elapsed_min, 2) if elapsed_min > 0 else 0
prev_fish[player] = {'fish': fish_now, 'ts': now}
```

---

## Variant Grouping Pattern (Critical)

Different variants of the same fish MUST use `name + "|" + variantId` as the dict key,
otherwise plain fish and galaxy fish get merged into one count.

```lua
-- Lua grouping:
local key = name .. "|" .. variantId   -- "Ancient Lochness Monster|Galaxy"
                                        -- "Ancient Lochness Monster|"

# Python merging:
key = f['name'] + '|' + f.get('variant', '')
```

---

## Files in This Project

| File | Role |
|---|---|
| `monitor.lua` | Main Lua script — reads ALL stats, runs every 30s |
| `autotrade.lua` | Simpler Lua — EVO/secrets only, no rod/quest |
| `tesdebug.lua` | Debug/probe script — dump DataReplion paths to log file |
| `server.py` | Flask aggregation server — `/report`, `/`, `/api/state` |
| `dashboard.html` | Web dashboard served at `:5000/` |
| `requirements.txt` | `flask`, `requests` |

---

## Debugging DataReplion Paths

When a path returns nil or wrong data, use this pattern in `tesdebug.lua`:

```lua
-- 1. Dump all top-level keys
local topData = DataReplion:Get({}) or {}
for k, v in pairs(topData) do print(type(v)=="table" and "[TABLE] "..k or k.." = "..tostring(v)) end

-- 2. Probe specific paths
local ok, val = pcall(function() return DataReplion:Get({"SomePath"}) end)
if ok and val ~= nil then -- found it!

-- 3. Write to log file for inspector analysis
writefile("debug.txt", table.concat(lines, "\n"))
```

---

## Discord Embed Tips

- **Max field value**: 1024 chars — always slice with `val[:1020]`
- **Inline fields**: Set `"inline": True` to show 2–3 cards side by side
- **Edit vs post**: Use `PATCH /webhooks/.../messages/{id}` to edit, `POST ?wait=true` to get new ID
- **Group by serverId** (short 8-char `game.JobId` prefix) not by player name
