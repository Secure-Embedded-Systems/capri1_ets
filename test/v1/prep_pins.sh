#!/usr/bin/env bash
sudo pkill -x openocd || true; sudo fuser -k 4444/tcp 3333/tcp 6666/tcp || true
sudo systemctl restart pigpiod

set -euo pipefail
HZ="${1:-1000000}"           # default 1 MHz; override: ./prep_pins_pwm.sh 2000000

log(){ printf '%s\n' "[prep] $*"; }

# daemon healthy
log "ensure pigpiod is running"
sudo systemctl start pigpiod || true
if ! timeout 1s pigs t >/dev/null 2>&1; then
  log "pigpio not responding; restarting"
  sudo systemctl restart pigpiod
  sleep 0.2
  timeout 1s pigs t >/dev/null 2>&1 || { log "FATAL: pigpio still not healthy"; exit 2; }
fi

# remove 1-Wire if it was using GPIO4; harmless if absent
sudo modprobe -r w1_therm w1_gpio 2>/dev/null || true

# TRST_n (17) and nRST (27) high (inactive)
raspi-gpio set 17 op dh
raspi-gpio set 27 op dh

# --- CLOCK on GPIO12 via hardware PWM (PWM0) ---
# Stop any previous PWM on 12, then start HZ @ 50% duty
timeout 1s pigs hp 12 0 0 || true
timeout 3s pigs hp 12 "${HZ}" $((HZ/2)) || { log "FATAL: pigs hp 12 ${HZ} failed"; exit 3; }
raspi-gpio get 12    # should show func=ALT0

# Fetch = GPIO22 OUTPUT low (raise after SRAM load)
raspi-gpio set 22 op dl

# JTAG parks: TMS high, TDI low (TCK/TDO driven by OpenOCD)

raspi-gpio set 13 op  
raspi-gpio set 6  op dh
raspi-gpio set 19 op dl
raspi-gpio set 8 ip 
#raspi-gpio set 26 ip 

# Scan pins
raspi-gpio set 21 op dl
raspi-gpio set 20 op dl
raspi-gpio set 16 op dl
raspi-gpio set 7  ip
#raspi-gpio set 12 ip || true   # ignore if still ALT0 (clock pin)

# User GPIOs
raspi-gpio set 25 ip
raspi-gpio set 24 ip

# capri1 cve2 status
raspi-gpio set 23 ip

# UART: Pi TX=GPIO14 OUTPUT, RX=GPIO15 INPUT
raspi-gpio set 14 op dl
raspi-gpio set 15 ip

log "status:"
for p in 17 27 12 22 6 13 19 8 21 20 16 7 25 24 23 14 15; do
  printf "GPIO%-2s: " "$p"; raspi-gpio get "$p" | awk '{print $0}'
done
log "Clock is now on GPIO12 (PWM0). Wire CAPRI1 clk_i to GPIO12."

