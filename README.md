# sl0ppy-SuriDash
Sl0ppy-SuriDash is a bash based dashboard for suricata in IDS or IPS Mode

# change log 
* added support for docker 

# sl0ppy-SuriDash Pre Requirements
* One must install suricata, jq.  
* Config suricata as IDS Preferable, or IPS both work for the dashboard.
* Make sure to configure suricata as IDS|IPS, with working socket, Then run the Dashboard

# Requirements 
```
sudo apt install jq suricata coreutils ncurses-bin
```
## Suricata-side requirements
* Suricata running with its command socket enabled — in suricata.yaml:

```
unix-command:
  enabled: yes
  filename: suricata-command.socket

```

# Install
```
sudo apt update
sudo apt install suricata jq   # suricata includes suricatasc + oinkmaster deps
```
* Debian/Ubuntu repos may carry an older Suricata. For 8.x use the OISF repo:
```
sudo apt install curl ca-certificates gnupg
curl -fsSL https://pages.suricata.io/repo.key | sudo gpg --dearmor -o /usr/share/keyrings/suricata-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/suricata-keyring.gpg] https://pages.suricata.io/repo/deb stable main" | sudo tee /etc/apt/sources.list.d/suricata.list
sudo apt update && sudo apt install suricata
```
# 2. Identify your sensor interface + networks
```
ip -br link                 # find the interface (e.g. ens18)
ip -4 addr show ens18       # your LAN range (e.g. 192.168.2.0/24)
```
# 3. Configure /etc/suricata/suricata.yaml
* Set these keys (they're scattered through the file):
```
vars:
  address-groups:
    HOME_NET: "[192.168.2.0/24]"      # your LAN
    EXTERNAL_NET: "!$HOME_NET"

default-rule-path: /var/lib/suricata/rules
rule-files:
  - "*.rules"

stats:
  enabled: yes
  interval: 2            # counters tick every 2s (matches the dashboard)

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert
        - anomaly
        - http
        - dns
        - tls
        - flows
  - fast:
      enabled: yes
      filename: fast.log

unix-command:
  enabled: yes
  filename: suricata-command.socket

```
# 4. Install rules (ETOpen — what your alerts use)
```
sudo suricata-update                    # fetches etopen.rules, writes to /var/lib/suricata/rules
sudo suricata-update list-sources        # optional: see catalogs
```
* To run it automatically (rules update daily):
```
sudo suricata-update --enable-source etpro/etopen   # if not already enabled
```


# 5. Validate + start
```
sudo suricata -T -c /etc/suricata/suricata.yaml -v    # config test: must say "success"
sudo systemctl enable --now suricata
sudo systemctl status suricata
```



# 6. Verify it's seeing traffic


```
sudo tail -f /var/log/suricata/eve.json | grep alert
sudo suricatasc -c version                              # socket alive
```



# 7. Point your dashboard at it
Your dashboard reads the socket (/run/suricata/suricata-command.socket — the default it auto-discovers), eve.json, and fast.log from /var/log/suricata/, all of which the above sets up. Then:

```
sudo ./sl0ppy-SuriDash
```



* IDS vs IPS note: the dashboard is read-only and works with either mode. You're currently in IDS mode (monitor + alert). Only switch to IPS (NFQUEUE inline blocking) if you actually want Suricata to drop packets that requires routing traffic through NFQUEUE rules and is a bigger change:



# IPS mode (only if wanted):
# suricata.yaml: nfq-log drop decisions, then route traffic:
```
sudo iptables -I INPUT -p tcp -j NFQUEUE --queue-num 0
sudo iptables -I OUTPUT -p tcp -j NFQUEUE --queue-num 0
```

# Docker Install
```
# put suridash.sh, Dockerfile, entrypoint.sh, suricata.yaml and ./rules in one dir
docker compose build
docker compose up -d suricata          # start the sensor
docker compose run --rm suridash       # attach the live dashboard
docker compose run --rm suridash --check   # verify counter mapping
```


# Usage 
```

Usage: sudo $0 [options]

  -i, --interval SEC    refresh interval in seconds (default ${REFRESH_INTERVAL})
      --once            print one frame and exit (no interactive UI)
      --check           list every counter, its value and the stats key it
                        resolved from (verifies the mapping on your build)
      --debug-counters  dump every numeric key your Suricata exposes
  -V, --version         print version
  -h, --help            this help

Keys:  q quit | p pause | r refresh now | j/k or arrows scroll | PgUp/PgDn,
       space/b page | g top | G bottom

```

# yours x0xr00t
