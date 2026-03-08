from flask import Flask, request, jsonify
import requests
import threading
import time
from datetime import datetime

app = Flask(__name__)

WEBHOOK_URL     = "https://discord.com/api/webhooks/1451564778228289614/K4HvDOilU7Up03GVD5LaupK3Rv-a5xm6kRZW13PSK0yusfACaIYmFeyMszJh40QGThjY"
UPDATE_INTERVAL = 30  # seconds between Discord edits

# Thread-safe store
# player_data[player] = {
#   hwid, serverId, evo,
#   secrets:     [ {name, qty, variant} ]   <- Tier 7, all fish
#   ruby_gem:    int                         <- Tier 5 Ruby+Gemstone count
#   secretTotal: int,
#   last_seen:   float
# }
player_data = {}
data_lock   = threading.Lock()
msg_id      = None

# Fish/min tracking: { player: {fish_caught, timestamp} }
prev_fish    = {}
SERVER_START = time.time()  # for uptime display

# ── /report endpoint ─────────────────────────────────────────────────
@app.route('/report', methods=['POST'])
def report():
    data = request.get_json(silent=True)
    if not data or 'player' not in data:
        return jsonify({"error": "Invalid payload"}), 400

    player = data['player']
    now    = time.time()
    data['last_seen'] = now

    # Compute fish/min from delta
    stats      = data.get('stats', {})
    fish_now   = stats.get('fishCaught', 0)
    data['fpm'] = 0.0

    with data_lock:
        if player in prev_fish:
            prev = prev_fish[player]
            elapsed_min = (now - prev['ts']) / 60.0
            if elapsed_min > 0:
                delta = fish_now - prev['fish']
                data['fpm'] = round(max(delta, 0) / elapsed_min, 2)
        prev_fish[player] = {'fish': fish_now, 'ts': now}
        player_data[player] = data

    return jsonify({"status": "ok", "fpm": data['fpm']}), 200

# ── Discord embed builder (mirrors index.html dashboard layout) ──────
def build_embed(snapshot):
    # ── Group by serverId ────────────────────────────────────────────
    servers = {}
    for player in sorted(snapshot.keys()):
        d = snapshot[player]
        sid = d.get('serverId', 'unknown')
        servers.setdefault(sid, []).append((player, d))

    # ── Global aggregates (header bar) ───────────────────────────────
    total_accounts  = len(snapshot)
    total_evo       = 0
    total_sctb      = 0
    total_ruby      = 0
    total_t7        = 0
    global_fpm_sum  = 0.0

    fields = []

    for server_id, members in sorted(servers.items()):
        srv_evo   = sum(m[1].get('evo', 0)      for m in members)
        srv_sctb  = sum(m[1].get('sctb', 0)     for m in members)
        srv_ruby  = sum(m[1].get('ruby_gem', 0) for m in members)
        srv_fpm   = sum(m[1].get('fpm', 0.0)    for m in members)
        srv_fph   = round(srv_fpm * 60)

        # Merge Tier-7 fish counts across players in this server
        merged_t7 = {}
        for _, d in members:
            for f in d.get('secrets', []):
                key = f['name'] + '|' + f.get('variant', '')
                if key not in merged_t7:
                    merged_t7[key] = dict(f)
                else:
                    merged_t7[key]['qty'] += f.get('qty', 0)

        srv_t7_total = sum(f['qty'] for f in merged_t7.values())

        total_evo      += srv_evo
        total_sctb     += srv_sctb
        total_ruby     += srv_ruby
        total_t7       += srv_t7_total
        global_fpm_sum += srv_fpm

        # ── Per-server card header (mirrors exsum in HTML) ──────────
        card_header = (
            f"`{len(members)}` bots | "
            f"⚡ `{round(srv_fpm, 2)}` FPM `{srv_fph}` FPH | "
            f"💎 EVO `{srv_evo}` | 🐟 SCTB `{srv_sctb}`\n"
        )

        # ── Secret (T7) fish lines ───────────────────────────────────
        t7_lines = ''
        for f in sorted(merged_t7.values(), key=lambda x: x['qty'], reverse=True):
            vtag = f" [{f['variant']}]" if f.get('variant') else ''
            t7_lines += f"> {f['name']}{vtag}: `{f['qty']}`\n"
        if not t7_lines and srv_t7_total == 0:
            t7_lines = '> *(none)*\n'

        # ── Per-player rows (mirrors playerHtml in the HTML) ─────────
        player_rows = ''
        for p, d in members:
            s      = d.get('stats', {})
            fc     = s.get('fishCaught', 0)
            fpm_p  = d.get('fpm', 0.0)
            rod    = d.get('rod', '?')
            quest  = d.get('quest', {})
            qlabel = quest.get('label', 'No Quest') if isinstance(quest, dict) else 'No Quest'
            # shorten quest label to keep field under 1024 chars
            if len(qlabel) > 40:
                qlabel = qlabel[:37] + '...'
            player_rows += (
                f"> 🟢 `{p}` — 🎣 `{fc:,}` | ⚡`{fpm_p}` fpm\n"
                f">   🎣 Rod: `{rod}` | 📋 {qlabel}\n"
            )

        val = card_header + player_rows
        if t7_lines:
            val += f"🐟 **T7 Fish:**\n{t7_lines}"

        fields.append({
            "name":   f"🖥️ Server `{server_id}` — {len(members)} acct(s)  |  FPH `{srv_fph}`",
            "value":  val[:1020],
            "inline": True
        })

    # ── Uptime ───────────────────────────────────────────────────────
    elapsed = int(time.time() - SERVER_START)
    h, rem  = divmod(elapsed, 3600)
    m, s    = divmod(rem, 60)
    uptime  = f"{h}h {m}m {s}s"

    time_str   = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    global_fph = round(global_fpm_sum * 60)

    # ── Global header bar (mirrors stat cards at top of HTML) ────────
    description = (
        f"🕒 `{time_str}` | ⏱️ `{uptime}`\n"
        f"```\n"
        f"{'ACCOUNTS':<12} {'FPH':<10} {'FPM':<10} {'EVO':<8} {'SCTB':<8} {'T7 FISH'}\n"
        f"{total_accounts:<12} {global_fph:<10} {round(global_fpm_sum,2):<10} "
        f"{total_evo:<8} {total_sctb:<8} {total_t7}\n"
        f"```"
    )

    color = 0x2ECC71
    if total_evo < 100 * max(total_accounts, 1): color = 0xF39C12
    if total_evo < 50  * max(total_accounts, 1): color = 0xE74C3C

    return {
        "title":       "📋 Fleet Command Center",
        "description": description,
        "color":       color,
        "fields":      fields,
        "footer":      {"text": f"TrackStat • up {uptime}"}
    }

# ── Web dashboard routes ──────────────────────────────────────────────
@app.route('/')
def dashboard():
    from flask import send_from_directory
    return send_from_directory('.', 'dashboard.html')

@app.route('/api/state')
def api_state():
    with data_lock:
        snapshot = dict(player_data)

    now = time.time()
    # Group by serverId
    servers = {}
    for player, d in snapshot.items():
        sid = d.get('serverId', 'unknown')
        servers.setdefault(sid, []).append(player)

    # Build grouped response
    server_groups = {}
    for sid, players in servers.items():
        members = [(p, snapshot[p]) for p in players]
        srv_evo  = sum(d.get('evo', 0)      for _, d in members)
        srv_sctb = sum(d.get('sctb', 0)     for _, d in members)
        srv_ruby = sum(d.get('ruby_gem', 0) for _, d in members)
        srv_fpm  = sum(d.get('fpm', 0.0)    for _, d in members)

        # Merge T7 fish
        merged_t7 = {}
        for _, d in members:
            for f in d.get('secrets', []):
                key = f['name'] + '|' + f.get('variant', '')
                if key not in merged_t7:
                    merged_t7[key] = dict(f)
                else:
                    merged_t7[key]['qty'] += f.get('qty', 0)

        player_list = []
        for p, d in members:
            s = d.get('stats', {})
            player_list.append({
                'name':       p,
                'hwid':       d.get('hwid', '?')[:8],
                'fishCaught': s.get('fishCaught', 0),
                'monthly':    s.get('monthlyFishCaught', 0),
                'secrets':    s.get('caughtSecrets', 0),
                'level':      s.get('monthlyLevel', 0),
                'fpm':        d.get('fpm', 0.0),
                'fph':        round(d.get('fpm', 0.0) * 60),
                'rod':        d.get('rod', 'Unknown'),
                'quest':      d.get('quest', {}).get('label', 'No Quest') if isinstance(d.get('quest'), dict) else 'No Quest',
                'evo':        d.get('evo', 0),
                'sctb':       d.get('sctb', 0),
                'last_seen':  round(now - d.get('last_seen', now)),  # seconds ago
            })

        server_groups[sid] = {
            'players':  player_list,
            'evo':      srv_evo,
            'sctb':     srv_sctb,
            'ruby':     srv_ruby,
            'fpm':      round(srv_fpm, 2),
            'fph':      round(srv_fpm * 60),
            't7_fish':  sorted(merged_t7.values(), key=lambda x: x['qty'], reverse=True),
        }

    # Global totals
    elapsed = int(time.time() - SERVER_START)
    h, rem  = divmod(elapsed, 3600)
    mn, s   = divmod(rem, 60)

    total_fpm = sum(d.get('fpm', 0.0) for d in snapshot.values())
    return jsonify({
        'servers':    server_groups,
        'total':      len(snapshot),
        'total_evo':  sum(d.get('evo', 0)  for d in snapshot.values()),
        'total_sctb': sum(d.get('sctb', 0) for d in snapshot.values()),
        'total_fpm':  round(total_fpm, 2),
        'total_fph':  round(total_fpm * 60),
        'uptime':     f"{h}h {mn}m {s}s",
        'timestamp':  datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    })

# ── Background Discord updater ───────────────────────────────────────
def discord_updater():
    global msg_id
    while True:
        time.sleep(UPDATE_INTERVAL)

        with data_lock:
            # Evict stale players (not reported in > 5 min)
            now = time.time()
            stale = [p for p, d in player_data.items() if now - d['last_seen'] > 300]
            for p in stale:
                del player_data[p]
                print(f"[Evict] {p} removed (stale)")

            if not player_data:
                continue

            snapshot = dict(player_data)   # work on a copy

        embed   = build_embed(snapshot)
        payload = {"embeds": [embed]}

        try:
            if msg_id:
                r = requests.patch(f"{WEBHOOK_URL}/messages/{msg_id}", json=payload, timeout=10)
                if r.status_code == 404:
                    print("[Discord] Message deleted — will re-post")
                    msg_id = None
                elif r.status_code == 200:
                    print(f"[Discord] Edited | {len(snapshot)} player(s)")
                else:
                    print(f"[Discord] PATCH {r.status_code}: {r.text[:200]}")

            if not msg_id:
                r = requests.post(f"{WEBHOOK_URL}?wait=true", json=payload, timeout=10)
                if r.status_code == 200:
                    msg_id = r.json().get('id')
                    print(f"[Discord] Posted | id={msg_id}")
                else:
                    print(f"[Discord] POST {r.status_code}: {r.text[:200]}")

        except Exception as e:
            print(f"[Discord] Error: {e}")

if __name__ == '__main__':
    threading.Thread(target=discord_updater, daemon=True).start()
    print("🚀 TrackStat Server — port 5000")
    # threaded=True so Flask handles concurrent requests properly
    app.run(host='0.0.0.0', port=5000, threaded=True)
