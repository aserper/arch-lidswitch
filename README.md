# Hyprland Lid Switch Handler

An automatic lid switch handler for Hyprland that intelligently manages monitor configuration when using a laptop
with external displays.

## Features

- 🔄 **Automatic Monitor Management**: Seamlessly switches between laptop and external monitors based on lid state
- 🖥️ **Smart Detection**: Automatically detects laptop screen (eDP-*) and external monitors (DP-*/HDMI-*/USB-C-*)
- ⚡ **Instant Response**: Real-time lid state monitoring with ~1 second response time  
- 🛡️ **Safe Implementation**: Uses Hyprland's native `hyprctl` commands - no dangerous systemd modifications
- 🔧 **Zero Configuration**: Works out of the box after installation
- 📝 **Comprehensive Logging**: Debug-friendly logs for troubleshooting
- 🔁 **Automatic Startup**: Systemd user service starts with your session
- 💤 **Smart Power Management**: Hibernates when lid closes without any external monitors

## How It Works

### Lid Closed + External Monitors Connected
- Disables laptop internal display
- External monitors becomes the primary displays
- All workspaces remain accessible

### Lid Opened
- Re-enables laptop internal display  
- Restores multi-monitor configuration
- Maintains your workspace layout

### Lid Closed + No External Monitors
- Hibernates the system automatically

## Requirements

- **OS**: Arch Linux (or similar)
- **Desktop**: Hyprland window manager
- **Hardware**: Laptop with ACPI lid switch support
- **Session**: Wayland session

## Installation

1. **Clone the repository**:
```bash
git clone https://github.com/aserper/arch-lidswitch
```

2. **Change to the repository directory**:
```bash
cd arch-lidswitch
```

3. **Make the script executable**:
```bash
chmod +x install-hyprland-lid-switch.sh # Hyprland <= 0.54
chmod +x install-hyprland-lid-switch-lua.sh # Hyprland 0.55+
```

4. **Run the script**:
```bash
./install-hyprland-lid-switch.sh # Hyprland <= 0.54
./install-hyprland-lid-switch-lua.sh # Hyprland 0.55+
```
5. **Test the installation**:
   Close your laptop lid to verify it works!

## What Gets Installed

The installer creates the following files:

```
~/.config/hypr/scripts/
├── lid-switch.sh      # Core lid switch logic
└── lid-monitor.sh     # Background monitor daemon

~/.config/systemd/user/
└── lid-monitor.service # Systemd service configuration
```

## Usage

### Service Management

```bash
# Check service status
systemctl --user status lid-monitor.service

# Start service
systemctl --user start lid-monitor.service

# Stop service  
systemctl --user stop lid-monitor.service

# Restart service
systemctl --user restart lid-monitor.service

# Disable auto-start
systemctl --user disable lid-monitor.service

# Re-enable auto-start
systemctl --user enable lid-monitor.service
```

### Manual Testing

```bash
# Test lid close behavior
~/.config/hypr/scripts/lid-switch.sh close

# Test lid open behavior
~/.config/hypr/scripts/lid-switch.sh open

# Auto-detect current lid state
~/.config/hypr/scripts/lid-switch.sh
```

### Monitoring Logs

```bash
# View monitor daemon logs
tail -f /tmp/hypr-lid-monitor.log

# View switch action logs  
tail -f /tmp/hypr-lid-switch.log

# View systemd service logs
journalctl --user -u lid-monitor.service -f
```

## Troubleshooting

### Service Not Starting

1. **Check service status**:
   ```bash
   systemctl --user status lid-monitor.service
   ```

2. **Verify Hyprland is running**:
   ```bash
   echo $XDG_SESSION_TYPE  # Should output 'wayland'
   hyprctl monitors        # Should list your monitors
   ```

3. **Check lid detection**:
   ```bash
   cat /proc/acpi/button/lid/*/state
   ```

### Lid Events Not Detected

1. **Verify ACPI support**:
   ```bash
   ls /proc/acpi/button/lid/
   ```
   
2. **Check for alternative lid detection**:
   ```bash
   find /sys -name "*lid*" -type f 2>/dev/null
   ```

3. **Manual detection test**:
   ```bash
   ~/.config/hypr/scripts/lid-monitor.sh
   # Check /tmp/hypr-lid-monitor.log for state changes
   ```

### Wrong Monitor Detection

1. **List current monitors**:
   ```bash
   hyprctl monitors
   ```

2. **Edit the configuration** in `~/.config/hypr/scripts/lid-switch.sh`:
   ```bash
   # Update LAPTOP_DISPLAY variable if needed
   LAPTOP_DISPLAY="your-laptop-monitor-name"
   ```

3. **Restart the service**:
   ```bash
   systemctl --user restart lid-monitor.service
   ```

## Customization

### Monitor Resolution and Positioning

Edit `~/.config/hypr/scripts/lid-switch.sh` to customize monitor settings:

#### Hyprland <= 0.54
In the `handle_lid_open()` function, modify these lines:
```bash
hyprctl keyword monitor "$LAPTOP_DISPLAY,2880x1920@120,0x0,2"
hyprctl keyword monitor "$CURRENT_EXTERNAL,5120x1440@144,1440x0,1"
```

#### Hyprland 0.55+
Set each of your monitor's resolution in your `hyprland.lua` file:
```bash
hl.monitor({ output = "eDP-1", mode = "2880x1920", position = "0x0", scale = 2 })
hl.monitor({ output = "DP-2", mode = "5120x1440", position = "1440x0", scale = 1 })
```

### Logging

Disable logging by commenting out `log_message` calls or redirect to `/dev/null`:

```bash
LOG_FILE="/dev/null"
```

## Uninstallation

```bash
# Stop and disable service
systemctl --user stop lid-monitor.service
systemctl --user disable lid-monitor.service

# Remove files
rm -f ~/.config/hypr/scripts/lid-switch.sh
rm -f ~/.config/hypr/scripts/lid-monitor.sh  
rm -f ~/.config/systemd/user/lid-monitor.service

# Clean up logs
rm -f /tmp/hypr-lid-*.log

# Reload systemd
systemctl --user daemon-reload
```
