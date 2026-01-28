# CJDNS Peer Yeeter

Interactive program which provides a user-friendly interaction with cjdnstool. Yeet, add, view, and manage peers with ease! Simplifies configuration options and more. Features an automatically updated database of public CJDNS nodes, which tracks peer connectivity and quality over time.

## Features

- **Discover peers** from GitHub repositories and public peer lists
- **Test connectivity** before adding peers to your config
- **Track peer quality** with SQLite database (quality scores, uptime history)
- **Manage both IPv4 and IPv6** peers with automatic interface detection
- **Runtime vs Permanent** peer management (test peers without modifying config)
- **Create automatic backups** before any config changes
- **Interactive menus** with gum-based UI for easy peer selection

## Prerequisites

### Required System Tools

```bash
sudo apt-get install jq git wget curl sqlite3
```

### cjdnstool (Required)

You need cjdnstool to communicate with your cjdns instance:

**Recommended - Node.js version (If not installed, will ask first run):**
```bash
sudo npm install -g cjdnstool
```
**May also work fine with the rust version. Did some limited testing.**
### gum (Required for Interactive UI)

The tool will offer to install gum automatically on first run, or just install manually if you want.

### Other Tools
- **fx** - Interactive JSON viewer/editor with mouse support (`sudo snap install fx`)
- **fzf** - Fuzzy finder for file selection (`sudo apt install fzf`)

## Installation

```bash
git clone https://github.com/mbhillrn/CJDNS-Peer-Yeeter.git ~/c-peeryeeter
cd ~/c-peeryeeter
sudo ./peeryeeter.sh
```

## Quick Start

### What Happens on Startup

When you run `sudo ./peeryeeter.sh`, the program automatically:

1. **Checks prerequisites** - Verifies jq, git, wget, sqlite3, gum are installed
2. **Detects cjdnstool** - Finds and validates your cjdnstool installation
3. **Finds your CJDNS config** - Scans systemd services for cjdns and locates config file
4. **Extracts admin credentials** - Gets admin.bind and admin.password from config
5. **Locates cjdroute binary** - Finds the binary for config validation
6. **Validates your config** - Checks JSON structure and runs `cjdroute --check`
7. **Tests admin connection** - Confirms communication with running CJDNS instance
8. **Initializes database** - Sets up SQLite peer tracking database and downloads peer lists

No manual configuration needed - everything is auto-detected!

### Main Menu Overview

```
CJDNS Peer Options:
  1) View Peer Status
     └─ Current peer connections and health from running cjdns

  2) Temporary Peer Functions (Runtime - no restart needed)
     └─ Add peers temporarily or disconnect running peers

  3) Permanent Peer Functions (Config - requires restart)
     └─ Add/remove peers permanently to config file

Config File Options:
  4) Edit Configuration File
     └─ Interactive JSON editor for all config sections

  5) Configuration File Management
     └─ Backup/restore, import/export, manage backups

Peer Yeeter Program Settings:
  6) Test Discovery & Preview Peers
     └─ Update local database and preview available peers

  7) Peer Yeeter Settings
     └─ Program configuration, peer sources, database management

Services/Quit:
  8) Restart CJDNS Service
     └─ Restart cjdns to apply config changes

  0) Exit Peer Yeeter!
```

### Submenu Details

**Option 2 - Temporary Peer Functions:**
- View Status & Disconnect Peers (real-time management via cjdnstool)
- Peer Adding Wizard (add peers without config modification)

**Option 3 - Permanent Peer Functions:**
- View Status & Remove Peers (interactive removal with quality metrics)
- Peer Adding Wizard (full workflow: discover, test, preview, apply to config)

**Option 5 - Configuration File Management:**
- View Current Config
- Edit with gum or Text Editor (micro/nano/vim/vi)
- Manage Backups (list, restore, delete)
- Cleanup/Normalize Config (remove extra metadata)
- Import/Export Peers

**Option 7 - Peer Yeeter Settings:**
- Program Settings (config path, service name, backup directory)
- Online Sources Management (enable/disable peer sources)
- Local Address Database Management (backup/restore/reset)

### Recommended Workflows

**Adding new peers permanently:**
1. Run `sudo ./peeryeeter.sh`
2. Select **Permanent Peer Functions** (option 3)
3. Choose **Peer Adding Wizard**
4. Select IPv4, IPv6, or both
5. Let it discover and optionally test peers
6. Review and apply changes
7. Restart CJDNS when prompted

**Testing peers before committing:**
1. Select **Temporary Peer Functions** (option 2)
2. Choose **Peer Adding Wizard**
3. Add peers to running instance (no config changes)
4. Monitor with **View Peer Status** (option 1)
5. If happy, add permanently via option 3

**Cleaning up bad peers:**
1. Select **Permanent Peer Functions** (option 3)
2. Choose **View Status & Remove Peers**
3. Use interactive selector to pick unresponsive peers
4. Confirm removal

## How It Works

### Peer Sources

Discovers peers from multiple configurable sources:
- `hyperboria/peers` (GitHub)
- `yangm97/peers` (GitHub)
- `cwinfo/hyperboria-peers` (GitHub)
- `kaotisk-hund` JSON peer list

Manage sources via **Peer Yeeter Settings** > **Online Sources Management**.

### Peer Quality Tracking

The SQLite database tracks:
- Connection state (ESTABLISHED/UNRESPONSIVE)
- First and last seen timestamps
- Quality score (0-100% based on uptime)
- Consecutive checks in current state

Peers are sorted by quality when displayed, helping you identify reliable nodes.

### Safe Config Handling

- Creates timestamped backups before every change
- Validates JSON syntax
- Validates with `cjdroute --check`
- Only writes required fields (password, publicKey)
- Strips unnecessary metadata from peer entries

## File Locations

```
/etc/cjdns_backups/
├── master_peer_list.json      # Cached discovered peers
├── peer_sources.json          # Configurable peer sources
├── peer_tracking.db           # SQLite quality database
├── cjdroute_backup_*.conf     # Config backups (timestamped)
└── database_backups/          # Database snapshots
```

## Project Structure

```
CJDNS-Peer-Yeeter/
├── peeryeeter.sh          # Main script
├── lib/
│   ├── ui.sh              # Colors, prompts, formatting, ASCII art
│   ├── detect.sh          # Auto-detection logic
│   ├── peers.sh           # Peer discovery and testing
│   ├── config.sh          # Config file management
│   ├── database.sh        # SQLite peer tracking
│   ├── master_list.sh     # Peer cache management
│   ├── interactive.sh     # Gum-based menus
│   ├── editor.sh          # JSON editor
│   ├── guided_editor.sh   # Smart guided peer editor
│   └── prerequisites.sh   # Dependency installation
├── README.md
└── LICENSE
```

## License

MIT License - see [LICENSE](LICENSE)
