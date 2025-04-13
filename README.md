# WakeVM

Wake-on-LAN listener for Proxmox VMs and containers with live tag filtering

---

`WakeVM` is a lightweight Bash-based Wake-on-LAN listener for Proxmox VE. It watches for incoming magic packets on UDP port 9 and boots the corresponding VM or container based on MAC address. Includes live tag-based filtering, dynamic config reloading via `SIGUSR1`, and an optional inotify watcher to auto-refresh the MAC list when VM or LXC configs change.

It can be run interactively, or deployed as a `systemd` service for always-on functionality.

Ideal for homelabs, edge devices, or energy-efficient setups where you want to power up only what's needed — on demand.

---

## 🚀 Features

- ✅ Listens for magic WOL packets on UDP port 9
- ✅ Matches MAC addresses for Proxmox VMs and containers
- ✅ Supports optional tag filtering (`--tag-only`) for fine-grained control
- ✅ Auto-detects MACs via `qm config` and `pct config`
- ✅ Live config reload via `SIGUSR1` (no restart needed)
- ✅ Config watcher via `inotify` (auto-refreshes MAC list on Proxmox file changes)
- ✅ Debug mode, dry-run simulation, and clean shutdown
- ✅ Can be deployed as a `systemd` service

---

## 📦 Requirements

- Proxmox VE host (with `qm` and `pct` CLI tools)
- Bash
- The following tools installed:
  ```bash
  apt install socat xxd inotify-tools
  ```

---

## 🛠 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/nachobacanful/wakevm.git /opt/wakevm
```

### 2. (Optional) Add to PATH

You can symlink `wakevm.sh` to make it globally executable as `wakevm`:

```bash
ln -s /opt/wakevm/wakevm.sh /usr/local/bin/wakevm
chmod +x /usr/local/bin/wakevm
```

Now you can run:

```bash
wakevm --dry-run -e
```

Otherwise, just use `/opt/wakevm/wakevm.sh` directly.

---

## 🧩 Systemd Service (Optional)

To run `wakevm` as a background service that starts on boot:

### 1. Copy the systemd unit file

```bash
cp /opt/wakevm/wakevm.service /etc/systemd/system/wakevm.service
```

### 2. Reload systemd and enable the service

```bash
systemctl daemon-reload
systemctl enable wakevm.service
systemctl start wakevm.service
```

### 3. Check status and logs

```bash
systemctl status wakevm.service
journalctl -u wakevm.service -f
```

---

### 🔧 Service Behavior

The systemd unit is configured to run:

```bash
/opt/wakevm/wakevm.sh --tag-only
```

This ensures that only Proxmox guests tagged with `wol` are eligible for wake-on-LAN by default.  
**You can edit the `.service` file to disable tag-only mode if needed.**

---

## ⚙️ Usage

```bash
./wakevm [options]
```

### CLI Options

| Option                       | Description                                                              |
|-----------------------------|--------------------------------------------------------------------------|
| `-d`, `--debug`              | Print debug info (MACs discovered during config scan)                    |
| `-e`, `--tag-only`           | Enable tag filtering (only start guests with a specific tag)            |
| `--tag <name>`               | Set a custom tag to filter on (default: `wol`)                          |
| `-w`, `--disable-watcher`    | Disable inotify watcher (only scan configs once at startup)             |
| `--dry-run`                  | Simulate behavior — don't start guests                                  |
| `-h`, `--help`               | Show help message                                                        |

---

## 🔖 Tag Filtering (ACL-style behavior)

Tag filtering lets you define **which VMs or containers are WOL-eligible** — like a simple access control list (ACL):

- By default, the script looks for the tag `wol` in the guest's Proxmox config. Apply a tag to the VM/CT in the Proxmox GUI.
- Use `-e` or `--tag-only` to enable filtering
- Use `--tag <name>` to override the default tag
- Tag matching happens **only when a magic packet is received**, so the tag can be changed dynamically at runtime without restarting the script

### ✅ Example

Start only guests with the `wol`(default) tag:

```bash
./wakevm --tag-only
```

Use a custom tag:

```bash
./wakevm --tag-only --tag autoservice
```
Then add the tag to the  VM/CT in the Proxmox GUI

If a guest does not have the required tag, you'll see:

```
[WOL] MAC aa:bb:cc:dd:ee:ff matched vm:101 but tag 'wol' not found — skipping
```

### ⚠️ Tag Case Sensitivity

> **Proxmox automatically converts all tags to lowercase.**  
> This script is **case-sensitive**, so be sure to use lowercase tag names.

✅ Use:
```
--tag wol
```

🚫 Avoid:
```
--tag WOL
```

---

## 🧠 How It Works

1. Script scans all VM and container configs and maps their MAC addresses
2. `socat` listens on UDP port 9 and writes packets to a named pipe
3. When a magic packet arrives:
   - The script extracts the MAC address
   - Looks it up in the map
   - (If `--tag-only` is used) checks if the guest has the right tag
   - Starts the guest using `qm start` or `pct start`

---

## 📡 Signals

- Send `SIGUSR1` to the script to manually reload the MAC list:

```bash
kill -USR1 <pid>
```

Useful when:
- You added or removed guests
- You updated tags
- Watcher was disabled via `--disable-watcher`

---

## 🧪 Examples

Dry-run with tag filtering:

```bash
./wakevm --dry-run -e
```

Minimal, no tag filtering:

```bash
./wakevm
```

Disable the config watcher (only load once):

```bash
./wakevm -w
```

---

## 🔒 Security Notes

- Script will **only start guests whose MACs are defined in Proxmox configs**
- Tag filtering gives you **live control over which guests are eligible for Wake-on-LAN**, without needing to restart the script
- Use VLANs/firewalls to control where WOL packets can be sent from
- Avoid exposing UDP port 9 to untrusted networks

---

## ✅ To-Do / Ideas

- [x] ~~`systemd` unit file for auto-start~~
- [x] ~~Logging to a file or syslog/journald~~
- [ ] ~~Live `SIGUSR2` to toggle debug mode~~
- [ ] Cooldown / rate limiting per guest. Some WOL tools send multiple packets
- [ ] Webhook or MQTT integration for WOL events

---

## 📝 License

This project is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html).

You are free to use, modify, and redistribute this software — even commercially — as long as:
- You provide proper attribution to **Ignacio Astaburuaga**/nachobacanful/[wakevm](https://github.com/nachobacanful/wakevm)
- Any modifications are also released under the same license (GPLv3)
- You make the source code available when redistributing

---

## 🛠 Maintained by

You — the person smart enough to automate their homelab 😎

Pull requests and forks welcome!
