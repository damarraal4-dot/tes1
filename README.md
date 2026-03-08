# 📦 Inventory Checker — Roblox → Discord

A Roblox exploit script that periodically reads the local player's inventory and sends a live status embed to a Discord webhook. Uses **Delta executor**'s auto-exec feature.

---

## Features

- ✅ Tracks specific items by **name** or **name + variant**
- ⚡ Counts **Evolved Enchant Stones** separately
- 🔒 Aggregates all untracked items as **Secret Items**
- 📨 **Creates** a new Discord message on first run, then **edits** it in-place on every subsequent update (no spam)
- 🎨 Color-coded embed based on EVO stone count (green / orange / red)
- 🕒 Configurable check interval (default: 30s)

---

## Setup

### 1. Edit the configuration block

Open `autotrade.lua` and change the values near the top:

```lua
local WEBHOOK_URL = "https://discord.com/api/webhooks/XXXXXXXXX/XXXXXXXXX"
local INTERVAL    = 30   -- seconds between each inventory check
```

### 2. Configure tracked items

Add or remove entries from `TRACK_ITEMS`:

```lua
local TRACK_ITEMS = {
    -- Match by item name only
    { label = "Sacred Guardian Squid", type = "name",    name = "Sacred Guardian Squid" },

    -- Match by item name AND a specific variant
    { label = "Ruby (Gemstone)",       type = "variant", name = "Ruby", variant = "Gemstone" },
}
```

| Field     | Description                                         |
|-----------|-----------------------------------------------------|
| `label`   | Display name shown in the Discord embed             |
| `type`    | `"name"` — match name only · `"variant"` — match name + variant |
| `name`    | Value of `data.Data.Name` in the game's item data   |
| `variant` | *(variant type only)* value inside `data.Variants`  |

### 3. Run via Delta auto-exec

Place `autotrade.lua` in Delta's **autoexec** folder. The script will execute automatically when you attach Delta to Roblox.

---

## Discord Embed Output

```
📦 PlayerName — Inventory
🕒 Update: 14:32:01 WIB
🎮 Server:  a1b2c3d4...

⚡ Batu EVO
> 120 pcs

📦 Item Tracked
> Sacred Guardian Squid: 2
> Ruby (Gemstone): 5

🔒 Secret Items
> Total: 38 item
```

**Embed color legend:**

| Color  | Condition        |
|--------|------------------|
| 🟢 Green  | EVO ≥ 100     |
| 🟡 Orange | EVO 50 – 99   |
| 🔴 Red    | EVO < 50      |

---

## How It Works

1. **`getInventory()`** — iterates `Inventory.Items` via Replion, resolves item data through `ItemUtility`, and tallies counts per tracked label.
2. **`buildEmbed()`** — constructs a Discord embed object with counts, timestamp, and color.
3. **`postMessage()` / `editMessage()`** — sends a `POST` on first run; saves the returned message ID to a local file (`inv_msg_<PlayerName>.txt`). Subsequent runs `PATCH` that message instead.
4. **Main loop** — calls `update()` once immediately, then every `INTERVAL` seconds.

---

## What Should Change

| Area | Issue | Suggested Fix |
|------|-------|---------------|
| **Webhook URL** | Hardcoded and committed as plain text | Move to a separate config file or inject at runtime; add the file to `.gitignore` |
| **`MSG_ID_FILE` path** | Saved in the executor's default directory with no cleanup | Consider a dedicated subfolder or clearing the file on game close |
| **Time timezone** | `os.date("%H:%M:%S")` is server-local time, labeled "WIB" | Either document that the offset may differ, or compute UTC+7 explicitly |
| **Error handling on `editMessage`** | Only returns `ok` but discards the HTTP response body | Log or print the error body to help debug 404 / rate-limit responses |
| **Rate limiting** | 30-second interval with a single webhook is fine, but no back-off on failure | Add exponential back-off or skip a cycle if the previous request failed |
| **Script file name** | File is `autotrade.lua` but the comment header says `inventory_checker.lua` | Rename the file (or the header) so they match |
