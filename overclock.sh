#!/bin/sh
LOG_FILE="./overclock.log"
LOG=1
overclock () {
  # --- Defaults ---
  # - Graphics Clock       = 100
  # - Memory Transfer Rate = 1300
  log "Overclocking with nvidia-settings"
  # Add or remove lines here depending on how many GPU's you have
  log "$(nvidia-settings -c :0 -a '[gpu:0]/GPUGraphicsClockOffset[3]=100' -a '[gpu:0]/GPUMemoryTransferRateOffset[3]=1300')"
  log "$(nvidia-settings -c :0 -a '[gpu:1]/GPUGraphicsClockOffset[3]=100' -a '[gpu:1]/GPUMemoryTransferRateOffset[3]=1300')"
}

abs_filename() {
  # $1 : relative filename
  filename="$1"
  parentdir="$(dirname "${filename}")"

  if [ -d "${filename}" ]; then
    cd "${filename}" && pwd
  elif [ -d "${parentdir}" ]; then
    echo "$(cd "${parentdir}" && pwd)/$(basename "${filename}")"
  fi
}

SCRIPT="$(abs_filename "$0")"

log() {
  if [ "$LOG" -eq 1 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S - ')$1" >> $LOG_FILE
  else
    echo "$1"
  fi
}

xserver_up() {
  # Give Xserver some time
  sleep 10
  if [ "$(ps ax | grep '[x]init' | wc -l)" = "1" ]; then
    log "An Xserver is running."
  else
    log "Error: No xinit found. Exiting"
    exit
  fi
}

install_svc() {
  log "Creating soystemd service(s)"
  if [ -n "$STARTX" ]; then
cat << EOF > /etc/systemd/system/nvidia-overclock-startx.service
[Unit]
Description=overclock NVIDIA GPUs
After=runlevel4.target
[Service]
Type=oneshot
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/etc/X11/.Xauthority"
ExecStart=/usr/bin/startx
[Install]
WantedBy=nvidia-overclock.service
EOF
  fi

cat << EOF > /etc/systemd/system/nvidia-overclock.service
[Unit]
Description=Overclock NVIDIA GPUs at system start
After=runlevel4.target
[Service]
Type=oneshot
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/etc/X11/.Xauthority"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$SCRIPT auto -l -x
[Install]
WantedBy=multi-user.target
EOF

  chmod 664 /etc/systemd/system/nvidia-overclock-startx.service
  chmod 664 /etc/systemd/system/nvidia-overclock.service
  log "Reloading systemd daemon.."
  systemctl daemon-reload
  systemctl enable nvidia-overclock-startx.service
  systemctl enable nvidia-overclock.service
  log "Services installation complete."
}

uninstall_svc() {
  # Remove services
  if [ -f "/etc/systemd/system/nvidia-overclock-startx.service" ]; then
    log "Uninstalling nvidia-overclock-startx.service.."
    systemctl disable nvidia-overclock-startx.service
    rm /etc/systemd/system/nvidia-overclock-startx.service
    RELOAD_SYSTEMD=1
  else
    log "No nvidia-overclock-startx.service file exists to uninstall."
  fi

  if [ -f "/etc/systemd/system/nvidia-overclock.service" ]; then
    log "Uninstalling nvidia-overclock.service.."
    systemctl disable nvidia-overclock.service
    rm /etc/systemd/system/nvidia-overclock.service
    RELOAD_SYSTEMD=1
  else
    log "No nvidia-overclock.service file exists to uninstall."
  fi

  # Reload systemd
  if [ -n "$RELOAD_SYSTEMD" ]; then
    log "Reloading systemd daemon.."
    systemctl daemon-reload
    systemctl reset-failed
    log "Service uninstall complete."
  fi
}

create_Xwrapper_config() {
  # Preserve the existing Xwrapper.config file if it exists
  if [ ! -f "/etc/X11/Xwrapper.config.orig" ]; then
    if [ -f "/etc/X11/Xwrapper.config" ]; then
      mv /etc/X11/Xwrapper.config /etc/X11/Xwrapper.config.orig
    fi
  else
    log "Error: Unable to move /etc/X11/Xwrapper.config."
    log "The file /etc/X11/Xwrapper.config.orig already exists. Please move or rename it."
    log "Exiting to avoid overwriting the existing file."
    exit
  fi


# Create a custom /etc/X11/Xwrapper.config if it does not already exist
if [ ! -f "/etc/X11/Xwrapper.config" ]; then
cat << EOF > /etc/X11/Xwrapper.config
allowed_users=anybody
needs_root_rights=yes
EOF
fi
}

restore_Xwrapper_config() {
  if [ -f "/etc/X11/Xwrapper.config" ]; then
    if [ "$(grep nvidia-overclock /etc/X11/Xwrapper.config | wc -l)" = "1" ]; then
      RESTORE_XWRAPPER=1
    else
      log "Existing /etc/X11/Xwrapper.config was not created by nvidia-overclock.sh."
      log "No restoration of the original file will be performed."
      return
    fi
  else
    RESTORE_XWRAPPER=1
  fi

  if [ -n "$RESTORE_XWRAPPER" ]; then
    if [ -f "/etc/X11/Xwrapper.config.orig" ]; then
      log "Found original Xwrapper.config file.  Restoring.."
      mv /etc/X11/Xwrapper.config.orig /etc/X11/Xwrapper.config
      log "Xwrapper.config file restored."
    else
      log "No original Xwrapper.config file found."
    fi
  fi
}

usage() {
cat << EOF
Usage:
  overclock.sh [COMMAND]
Commands:
  overclock
    It overclock your graphics card(s)
  auto [-l] [-x]
    -l logs everything
    -x checks if Xorg is working
  install-svc [-x]
    Makes a soystemd service to overclock the card(s)
  uninstall-svc
    Removes the soystemd service if it already exists
  help|--help|usage|--usage|?
    Shows this message
EOF
}

case $1 in
  overclock )
    overclock
    ;;
  auto )
    shift
    while getopts ":lx" OPTS; do
      case $OPTS in
        l ) LOG=1
	    shift
            ;;
        x ) xserver_up
	    shift
            ;;
      esac
    done

    overclock
    ;;
  install-svc )
    shift
    while getopts ":x" OPTS; do
      case $OPTS in
        x ) STARTX="/usr/bin/startx" && create_Xwrapper_config;;
      esac
    done

    install_svc
    ;;
  uninstall-svc )
    restore_Xwrapper_config
    uninstall_svc
    ;;
  help|--help|usage|--usage|\? )
    usage
    ;;
  * )
    usage
    ;;
esac
