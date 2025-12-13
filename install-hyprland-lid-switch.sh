#!/bin/bash

################################################################################
# Hyprland Lid Switch Installer
# 
# This script installs an automatic lid switch handler for Hyprland that:
# - Disables laptop display when lid is closed (with external monitor connected)
# - Re-enables laptop display when lid is opened
# - Works safely without crashing Wayland sessions
#
# Compatible with: Arch Linux, Hyprland, laptops with external monitors
# Author: https://github.com/aserper/hyprland-lid-switch
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HYPR_CONFIG_DIR="$HOME/.config/hypr"
SCRIPTS_DIR="$HYPR_CONFIG_DIR/scripts"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# Global variables
laptop_monitor=""
external_monitor=""

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if we're running Hyprland
check_hyprland() {
    if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]] || ! command_exists hyprctl; then
        log_error "This script requires Hyprland to be running"
        exit 1
    fi
}

# Detect laptop and external monitors
detect_monitors() {
    local monitor_list=""
    
    # Get monitor information from hyprctl
    monitor_list=$(hyprctl monitors | awk '/Monitor / {print $2}')

    laptop_monitor=$(grep -m1 "^eDP" <<<"${monitor_list}")
    external_monitor=$(grep -m1 -E "^(DP|HDMI|USB-C)" <<<"${monitor_list}")
    
    if [[ -z "$laptop_monitor" ]]; then
        log_error "Could not detect laptop monitor (eDP-*)"
        exit 1
    fi
    
    log_info "Detected laptop monitor: $laptop_monitor"
    if [[ -n "$external_monitor" ]]; then
        log_info "Detected external monitor: $external_monitor"
    else
        log_info "No external monitor currently connected"
    fi
}

# Create directories if they don't exist
create_directories() {
    log_info "Creating necessary directories..."
    
    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$SYSTEMD_USER_DIR"
    
    log_success "Directories created"
}

# Install the lid switch script
install_lid_switch_script() {
    local laptop_monitor="$1"
    
    log_info "Installing lid switch script..."
    
    cat > "$SCRIPTS_DIR/lid-switch.sh" << 'EOF'
#!/bin/bash

LAPTOP_DISPLAY="LAPTOP_MONITOR_PLACEHOLDER"
LOG_FILE="/tmp/hypr-lid-switch.log"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

get_lid_state() {
    cat /proc/acpi/button/lid/*/state 2>/dev/null | grep -q "closed" && echo "closed" || echo "open"
}

get_external_display() {
    # Dynamically get the external display name
    hyprctl monitors | grep -E "^Monitor (DP|HDMI|USB-C)" | grep -v "$LAPTOP_DISPLAY" | head -1 | cut -d' ' -f2
}

handle_lid_close() {
    log_message "Lid closed - checking for external monitor"
    
    CURRENT_EXTERNAL=$(get_external_display)
    if [[ -n "$CURRENT_EXTERNAL" ]]; then
        log_message "External monitor detected: $CURRENT_EXTERNAL, disabling laptop display"
        hyprctl keyword monitor "$LAPTOP_DISPLAY,disable" || log_message "Failed to disable laptop display"
        log_message "Laptop display disabled, $CURRENT_EXTERNAL remains as primary"
    else
        log_message "No external monitor detected, hibernating system"
        systemctl hibernate
    fi
}

handle_lid_open() {
    log_message "Lid opened - re-enabling laptop display"
    
    CURRENT_EXTERNAL=$(get_external_display)
    if [[ -n "$CURRENT_EXTERNAL" ]]; then
        log_message "External monitor detected: $CURRENT_EXTERNAL, setting up dual monitor configuration"
        hyprctl keyword monitor "$LAPTOP_DISPLAY,2880x1920@120,0x0,2" || log_message "Failed to enable laptop display"
        log_message "Dual monitor setup restored with $CURRENT_EXTERNAL"
    else
        log_message "No external monitor, enabling laptop display only"
        hyprctl keyword monitor "$LAPTOP_DISPLAY,2880x1920@120,0x0,2" || log_message "Failed to enable laptop display"
    fi
}

case "$1" in
    "close")
        handle_lid_close
        ;;
    "open")
        handle_lid_open
        ;;
    *)
        lid_state=$(get_lid_state)
        log_message "Auto-detecting lid state: $lid_state"
        
        if [[ "$lid_state" == "closed" ]]; then
            handle_lid_close
        else
            handle_lid_open
        fi
        ;;
esac
EOF

    # Replace placeholder with actual laptop monitor
    sed -i "s/LAPTOP_MONITOR_PLACEHOLDER/$laptop_monitor/g" "$SCRIPTS_DIR/lid-switch.sh"
    
    # Make script executable
    chmod +x "$SCRIPTS_DIR/lid-switch.sh"
    
    log_success "Lid switch script installed at $SCRIPTS_DIR/lid-switch.sh"
}

# Install the lid monitor script
install_lid_monitor_script() {
    log_info "Installing lid monitor script..."
    
    cat > "$SCRIPTS_DIR/lid-monitor.sh" << 'EOF'
#!/bin/bash

# Hyprland Lid State Monitor
# This script continuously monitors the lid state and triggers the appropriate action

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LID_SWITCH_SCRIPT="$SCRIPT_DIR/lid-switch.sh"
LOG_FILE="/tmp/hypr-lid-monitor.log"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

get_lid_state() {
    if [[ -f /proc/acpi/button/lid/LID0/state ]]; then
        local state_line=$(cat /proc/acpi/button/lid/LID0/state 2>/dev/null)
        if [[ "$state_line" =~ closed ]]; then
            echo "closed"
        else
            echo "open"
        fi
    else
        # Fallback for systems without specific LID0
        if [[ -f /proc/acpi/button/lid/*/state ]]; then
            cat /proc/acpi/button/lid/*/state 2>/dev/null | grep -q "closed" && echo "closed" || echo "open"
        else
            echo "unknown"
        fi
    fi
}

# Initial state
previous_state=$(get_lid_state)
log_message "Lid monitor started, initial state: $previous_state"

while true; do
    current_state=$(get_lid_state)
    
    if [[ "$current_state" != "$previous_state" && "$current_state" != "unknown" ]]; then
        log_message "Lid state changed from $previous_state to $current_state"
        
        # Call the lid switch script with the appropriate argument
        if [[ "$current_state" == "closed" ]]; then
            "$LID_SWITCH_SCRIPT" close
        elif [[ "$current_state" == "open" ]]; then
            "$LID_SWITCH_SCRIPT" open
        fi
        
        previous_state="$current_state"
    fi
    
    sleep 1
done
EOF
    
    # Make script executable
    chmod +x "$SCRIPTS_DIR/lid-monitor.sh"
    
    log_success "Lid monitor script installed at $SCRIPTS_DIR/lid-monitor.sh"
}

# Install the systemd service
install_systemd_service() {
    log_info "Installing systemd user service..."
    
    cat > "$SYSTEMD_USER_DIR/lid-monitor.service" << EOF
[Unit]
Description=Hyprland Lid Switch Monitor
After=graphical-session.target

[Service]
Type=simple
ExecStart=$SCRIPTS_DIR/lid-monitor.sh
Restart=always
RestartSec=2
Environment="DISPLAY=:0"

[Install]
WantedBy=default.target
EOF
    
    log_success "Systemd service installed at $SYSTEMD_USER_DIR/lid-monitor.service"
}

# Enable and start the service
enable_service() {
    log_info "Enabling and starting lid monitor service..."
    
    # Reload systemd daemon
    systemctl --user daemon-reload
    
    # Enable service to start on boot
    systemctl --user enable lid-monitor.service
    
    # Start service now
    systemctl --user start lid-monitor.service
    
    # Check if service started successfully
    if systemctl --user is-active --quiet lid-monitor.service; then
        log_success "Lid monitor service is running"
    else
        log_error "Failed to start lid monitor service"
        systemctl --user status lid-monitor.service
        exit 1
    fi
}

# Check if lid detection is working
test_lid_detection() {
    log_info "Testing lid state detection..."
    
    if [[ -f /proc/acpi/button/lid/LID0/state ]]; then
        local lid_state=$(cat /proc/acpi/button/lid/LID0/state 2>/dev/null)
        log_success "Lid state detection working: $lid_state"
    elif [[ -f /proc/acpi/button/lid/*/state ]]; then
        local lid_state=$(cat /proc/acpi/button/lid/*/state 2>/dev/null)
        log_success "Lid state detection working: $lid_state"
    else
        log_warning "Could not find lid state files. The service may not work properly."
        log_info "Please check if your system supports ACPI lid events."
    fi
}

# Backup existing files
backup_existing_files() {
    log_info "Backing up existing files..."
    
    local backup_dir="$HYPR_CONFIG_DIR/scripts/.backup-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -f "$SCRIPTS_DIR/lid-switch.sh" ]] || [[ -f "$SCRIPTS_DIR/lid-monitor.sh" ]]; then
        mkdir -p "$backup_dir"
        
        [[ -f "$SCRIPTS_DIR/lid-switch.sh" ]] && cp "$SCRIPTS_DIR/lid-switch.sh" "$backup_dir/"
        [[ -f "$SCRIPTS_DIR/lid-monitor.sh" ]] && cp "$SCRIPTS_DIR/lid-monitor.sh" "$backup_dir/"
        
        log_success "Existing files backed up to $backup_dir"
    fi
}

# Print final instructions
print_final_instructions() {
    echo
    log_success "Installation completed successfully!"
    echo
    echo -e "${BLUE}What was installed:${NC}"
    echo "  • Lid switch handler script: $SCRIPTS_DIR/lid-switch.sh"
    echo "  • Lid monitor daemon: $SCRIPTS_DIR/lid-monitor.sh"
    echo "  • Systemd user service: lid-monitor.service"
    echo
    echo -e "${BLUE}How it works:${NC}"
    echo "  • When lid closes + external monitor connected: laptop screen turns off"
    echo "  • When lid opens: laptop screen turns back on (dual monitor setup)"
    echo "  • Service starts automatically on login"
    echo
    echo -e "${BLUE}Useful commands:${NC}"
    echo "  • Check service status: systemctl --user status lid-monitor.service"
    echo "  • View logs: tail -f /tmp/hypr-lid-monitor.log"
    echo "  • View switch logs: tail -f /tmp/hypr-lid-switch.log"
    echo "  • Stop service: systemctl --user stop lid-monitor.service"
    echo "  • Restart service: systemctl --user restart lid-monitor.service"
    echo
    echo -e "${GREEN}Try closing your laptop lid now to test!${NC}"
}

################################################################################
# Main Installation Process
################################################################################

main() {
    echo "=================================="
    echo "Hyprland Lid Switch Installer"
    echo "=================================="
    echo
    
    # Pre-installation checks
    log_info "Performing pre-installation checks..."
    check_hyprland
    
    # Detect monitors
    log_info "Detecting Monitors..."
    detect_monitors
    
    # Test lid detection
    test_lid_detection
    
    # Backup existing files
    backup_existing_files
    
    # Create directories
    create_directories
    
    # Install scripts and service
    install_lid_switch_script "$laptop_monitor"
    install_lid_monitor_script
    install_systemd_service
    
    # Enable and start service
    enable_service
    
    # Print final instructions
    print_final_instructions
}

# Handle script interruption
trap 'log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
