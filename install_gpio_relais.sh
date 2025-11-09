#!/bin/bash
# ====================================================
# GPIO Relais Installer mit optionalem Taster
# ====================================================
echo "=== GPIO Relais Installer ==="

# --- Relais GPIO abfragen ---
read -p "GPIO-Nummer für Relais (z. B. 17): " RELAIS_PIN

# --- Logikpegel abfragen ---
read -p "Ist dein Relais aktiv bei HIGH oder LOW? (high/low): " ACTIVE_LEVEL
if [[ "$ACTIVE_LEVEL" =~ ^[Hh] ]]; then
    ACTIVE_HIGH=True
else
    ACTIVE_HIGH=False
fi

# --- Boot-Verzögerung abfragen ---
read -p "Nach wie vielen Sekunden soll das Relais nach dem Boot eingeschaltet werden? (z. B. 5): " DELAY_TIME

# --- Tasterfunktion abfragen ---
read -p "Soll ein Taster zur Steuerung verwendet werden? (j/n): " USE_BUTTON
USE_BUTTON=${USE_BUTTON,,}  # in Kleinbuchstaben

if [[ "$USE_BUTTON" == "j" ]]; then
    BUTTON_ENABLED=True
    read -p "GPIO-Nummer für Taster (z. B. 27): " BUTTON_PIN
else
    BUTTON_ENABLED=False
    BUTTON_PIN=0
fi

# --- Python-Skript erstellen ---
echo "Erstelle /usr/local/bin/gpio_relais.py ..."
sudo tee /usr/local/bin/gpio_relais.py >/dev/null <<EOF
#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time
import signal
import sys

# === Konfiguration ===
RELAIS_PIN = $RELAIS_PIN
BUTTON_ENABLED = $BUTTON_ENABLED
BUTTON_PIN = $BUTTON_PIN
ACTIVE_HIGH = $ACTIVE_HIGH
LONG_PRESS_TIME = 5
DELAY_TIME = $DELAY_TIME

GPIO.setmode(GPIO.BCM)
GPIO.setup(RELAIS_PIN, GPIO.OUT)

if BUTTON_ENABLED:
    GPIO.setup(BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

# --- Relaisfunktionen ---
def relais_on():
    GPIO.output(RELAIS_PIN, GPIO.HIGH if ACTIVE_HIGH else GPIO.LOW)
    print("Relais EIN")
    sys.stdout.flush()

def relais_off():
    GPIO.output(RELAIS_PIN, GPIO.LOW if ACTIVE_HIGH else GPIO.HIGH)
    print("Relais AUS")
    sys.stdout.flush()

# --- Shutdown-Handler ---
def shutdown_handler(sig=None, frame=None):
    relais_off()
    GPIO.cleanup()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
signal.signal(signal.SIGINT, shutdown_handler)

# --- Boot-Verzögerung ---
relais_off()
time.sleep(DELAY_TIME)
relais_on()

# --- Tasterüberwachung ---
if BUTTON_ENABLED:
    press_start = None
    while True:
        input_state = GPIO.input(BUTTON_PIN)
        if input_state == GPIO.LOW and press_start is None:
            press_start = time.time()
        elif input_state == GPIO.HIGH and press_start is not None:
            press_duration = time.time() - press_start
            press_start = None
            if press_duration < LONG_PRESS_TIME:
                relais_off()
            else:
                relais_on()
        time.sleep(0.05)
else:
    while True:
        time.sleep(1)
EOF

# --- Systemd-Dienst erstellen ---
echo "Erstelle systemd-Dienst /etc/systemd/system/gpio_relais.service ..."
sudo tee /etc/systemd/system/gpio_relais.service >/dev/null <<EOF
[Unit]
Description=GPIO Relais Steuerung
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gpio_relais.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Berechtigungen
sudo chmod +x /usr/local/bin/gpio_relais.py
sudo systemctl daemon-reload
sudo systemctl enable gpio_relais.service
sudo systemctl start gpio_relais.service

echo ""
echo "=== ✅ Installation abgeschlossen ==="
echo "Relais-GPIO: $RELAIS_PIN"
echo "Relais aktiv bei $ACTIVE_LEVEL"
if [[ "$USE_BUTTON" == "j" ]]; then
    echo "Taster aktiviert (GPIO $BUTTON_PIN, langer Druck = EIN, kurzer = AUS)"
else
    echo "Taster nicht aktiviert"
fi
echo "Relais schaltet $DELAY_TIME Sekunden nach Boot ein."
echo "Relais wird beim Shutdown automatisch ausgeschaltet."
echo ""
echo "Dienst läuft: gpio_relais.service"
echo "Status prüfen mit: sudo systemctl status gpio_relais.service"
echo "Log ansehen mit: sudo journalctl -u gpio_relais.service -f"
