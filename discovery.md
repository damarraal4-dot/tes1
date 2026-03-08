# Game Data Structure — Discovery Notes

Discovered via `tesdebug.lua` on **2026-03-04**.

---

## ItemUtility — `GetItemData(id)` return shape

```
data
├── SellPrice       (number)       e.g. 26200
├── Weight          (table)
│   ├── Default     (number)       e.g. 2.4
│   └── Big         (number)       e.g. 3.2
├── _moduleScript   (string)       item display name, e.g. "Blob Fish"
├── Variants        (table)        list of variant strings (can be empty)
├── Probability     (table)
│   └── Chance      (number)       e.g. 0.00002
└── Data            (table)
    ├── Name        (string)       ★ item name used everywhere
    ├── Type        (string)       ★ category — e.g. "Fish", "Gemstone"
    ├── Tier        (number)       ★ rarity level — 1 (common) → 6 (highest)
    ├── Id          (number)       internal numeric id
    ├── Icon        (string)       rbxassetid://...
    └── Description (string)
```

## Inventory slot shape (from `DataReplion:Get({"Inventory","Items"})`)

```
slot
├── Id          (number)    matches GetItemData id
├── Quantity    (number)    stack count (defaults to 1 if absent)
├── Favorited   (boolean)
├── UUID        (string)    unique slot identifier
└── Metadata    (table)
    └── Weight  (number)    actual weight of this catch
```

---

## Key fields to use in scripts

| What you want | Path |
|---|---|
| Item name | `data.Data.Name` |
| Item category | `data.Data.Type` (e.g. `"Fish"`) |
| Rarity / tier | `data.Data.Tier` (number, 1–6) |
| Sell price | `data.SellPrice` |
| Variants list | `data.Variants` |
| Catch weight | `slot.Metadata.Weight` |

---

## Rarity tiers observed

| Tier | Rarity label (assumed) |
|---|---|
| 1 | Common |
| 2 | Uncommon |
| 3 | Rare |
| 4 | Epic |
| 5 | Legendary |
| 6 | Mytic |
| 7 | **Secret / highest** |

> [!NOTE]
> Tier labels (Common, Rare, etc.) are inferred — the game only stores the number. Confirm labels in-game if needed.

---

## Services & modules

| Name | Access path |
|---|---|
| `Replion` | `require(RS.Packages.Replion)` |
| `DataReplion` | `Replion.Client:WaitReplion("Data")` |
| `ItemUtility` | `require(RS.Shared.ItemUtility)` |
| Inventory items | `DataReplion:Get({"Inventory", "Items"})` |

---

## HTTP function name

On Delta executor the global is simply **`request()`**.
Fallback chain used in scripts:
```lua
local httpFn = request or (syn and syn.request) or (http and http.request) or http_request
```
