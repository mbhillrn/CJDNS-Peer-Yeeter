# CJDNS Peer Yeeter

A powerful interactive tool for managing CJDNS peers. Automatically discovers peers from multiple sources, tests connectivity, tracks peer quality over time, and safely manages your cjdns configuration.

## What It Does

- **Discovers peers** from GitHub repositories and public peer lists
- **Tests connectivity** before adding peers to your config
- **Tracks peer quality** with a SQLite database (quality scores, uptime history)
- **Manages both IPv4 and IPv6** peers with automatic interface detection
- **Creates automatic backups** before any config changes
- **Provides an interactive menu** with gum-based UI for easy peer selection

## Requirements

### System Dependencies

```bash
sudo apt-get install jq git wget sqlite3
```

### cjdnstool (Required)

You need cjdnstool to communicate with your cjdns instance:
- https://github.com/furetosan/cjdnstool

### gum (Interactive UI)

The tool will offer to install gum automatically on first run, or install manually:

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install gum
```

## Installation

```bash
git clone https://github.com/mbhillrn/CJDNS-Peer-Yeeter.git
cd CJDNS-Peer-Yeeter
sudo ./peeryeeter.sh
```

## Usage

Run with sudo (required for config access and service management):

```bash
sudo ./peeryeeter.sh
```

### Main Menu

```
1) Peer Adding Wizard (Recommended)
   Complete guided workflow: select protocols, discover peers,
   test connectivity, preview changes, and apply.

2) Discover & Preview Peers
   Fetch peers from all sources and see what's available.

3) Edit Config File
   Interactive JSON editor with validation.

4) View Status & Remove Peers
   See all peers with quality scores, select and remove bad ones.

5) View Peer Status
   Real-time peer statistics from cjdns.

6) Maintenance & Settings
   Config normalization, backup management, database tools,
   restart cjdns service.
```

### Recommended Workflow

**Adding new peers:**
1. Run `sudo ./peeryeeter.sh`
2. Select **Peer Adding Wizard** (option 1)
3. Choose IPv4, IPv6, or both
4. Let it discover and test peers
5. Review and apply changes

**Cleaning up bad peers:**
1. Run `sudo ./peeryeeter.sh`
2. Select **View Status & Remove Peers** (option 4)
3. Use the interactive selector to pick unresponsive peers
4. Confirm removal

## How It Works

### Auto-Detection

On startup, the tool automatically:
1. Scans systemd services for cjdns
2. Finds your config file location
3. Extracts admin connection info
4. Tests connection to cjdns
5. Locates your cjdroute binary

No manual configuration needed.

### Peer Sources

Discovers peers from:
- `hyperboria/peers` (GitHub)
- `yangm97/peers` (GitHub)
- `cwinfo/hyperboria-peers` (GitHub)
- `kaotisk-hund` JSON peer list

### Peer Quality Tracking

The SQLite database tracks:
- Connection state (ESTABLISHED/UNRESPONSIVE)
- First and last seen timestamps
- Quality score (0-100% based on uptime)
- Total check count

### Safe Config Handling

- Creates timestamped backups before every change
- Validates JSON syntax
- Validates with cjdroute --check
- Only writes required fields (password, publicKey)
- Strips unnecessary metadata from peer entries

## File Locations

```
/etc/cjdns_backups/
├── master_peer_list.json      # Cached discovered peers
├── peer_sources.json          # Configurable peer sources
├── peer_tracking.db           # SQLite quality database
├── cjdroute_backup_*.conf     # Config backups
└── database_backups/          # Database backups
```

## Project Structure

```
CJDNS-Peer-Yeeter/
├── peeryeeter.sh          # Main script
├── lib/
│   ├── ui.sh              # Colors, prompts, formatting
│   ├── detect.sh          # Auto-detection logic
│   ├── peers.sh           # Peer discovery and testing
│   ├── config.sh          # Config file management
│   ├── database.sh        # SQLite peer tracking
│   ├── master_list.sh     # Peer cache management
│   ├── interactive.sh     # Gum-based menus
│   ├── editor.sh          # JSON editor
│   ├── guided_editor.sh   # Smart guided editor
│   └── prerequisites.sh   # Dependency installation
├── README.md
└── LICENSE
```

## Troubleshooting

### "cjdnstool not found"

Install from: https://github.com/furetosan/cjdnstool

### "Cannot connect to cjdns admin interface"

Check if cjdns is running:
```bash
sudo systemctl status cjdroute
```

### "Config validation failed"

Your original config is safe (backup was created). Check the error message for details.

### "Failed to clone repository"

Some peer sources may be temporarily unavailable. The tool continues with working sources.

## License

MIT License - see [LICENSE](LICENSE)

---

## Donations

If this tool saved you time, consider donating:

**Bitcoin:** `YOUR_BTC_ADDRESS_HERE`

