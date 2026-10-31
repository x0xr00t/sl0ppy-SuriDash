![GitHub release](https://img.shields.io/github/v/release/x0xr00t/sl0ppy-SuriDash)
![GitHub license](https://img.shields.io/github/license/x0xr00t/sl0ppy-SuriDash)
![GitHub stars](https://img.shields.io/github/stars/x0xr00t/sl0ppy-SuriDash)
![GitHub issues](https://img.shields.io/github/issues/x0xr00t/sl0ppy-SuriDash)

# sl0ppy-SuriDash

**A Bash-based, read-only monitoring dashboard for [Suricata](https://suricata.io/), supporting IDS and IPS deployments.**

SuriDash displays Suricata runtime statistics and reads the configured Suricata command socket and log files. It does **not** configure firewall rules, switch capture modes, or perform packet blocking itself. Suricata's engine and inline capture path perform inspection and enforcement.

> **Version documented:** v1.5.1  
> **Author:** Patrick Hoogeveen — x0xr00t  
> **Team:** sl0ppyr00t

---

## Contents

- [What's new in v1.5.1](#whats-new-in-v151)
- [Requirements](#requirements)
- [Install](#install)
- [Identify interfaces and IP networks](#identify-interfaces-and-ip-networks)
- [Configure Suricata](#configure-suricata)
- [Configure the command socket](#configure-the-command-socket)
- [Install and update rules](#install-and-update-rules)
- [Validate and start Suricata](#validate-and-start-suricata)
- [IDS mode: passive monitoring](#ids-mode-passive-monitoring)
- [IPS mode A: AF_PACKET inline bridge](#ips-mode-a-af_packet-inline-bridge)
- [IPS mode B: NFQUEUE inline filtering](#ips-mode-b-nfqueue-inline-filtering)
- [Verify traffic and blocking](#verify-traffic-and-blocking)
- [Run SuriDash](#run-suridash)
- [Docker](#docker)
- [Troubleshooting](#troubleshooting)
- [Safe rollback](#safe-rollback)
- [Operational notes](#operational-notes)

---

## What's new in v1.5.1

Health-scoring refinements on top of v1.5:

- **Capture-drop penalty softened:** a single dropped packet in one statistics window no longer causes a disproportionate health-score reduction.
  - Drop-rate dead zone: windows below 0.5% incur no penalty.
  - Penalty weight: 3 points per full percentage point, capped at 30.
  - Two-consecutive-window rule: a drop penalty is applied only after drops appear in two consecutive windows.
- **Cosmetic penalties reduced:** fragment timeouts and bad checksums cost 1 point each instead of 2.
- **Reason reporting fixed:** active penalty explanations are appended to the reasons list so the displayed score can be investigated.

The health score is a dashboard heuristic. It is not a formal measure of network security, packet-delivery quality, or complete sensor coverage.

---

## Requirements

Recommended platform: Linux with Bash and a supported Suricata build.

On Debian, Kali, Ubuntu, and derivatives:

```bash
sudo apt update
sudo apt install -y suricata suricata-update jq coreutils ncurses-bin iproute2
```

Useful optional diagnostics:

```bash
sudo apt install -y ethtool tcpdump nftables iptables
```

Check installed versions and available commands:

```bash
suricata --build-info
suricata --version
suricatasc --help
jq --version
bash --version
```

SuriDash itself is a Bash dashboard. Run it with Bash, not `sh`:

```bash
bash ./sl0ppy-SuriDash
```

If the repository's executable is named differently, use that exact filename.

### Suricata version

Distribution repositories can ship different Suricata versions. Use the official [Suricata installation documentation](https://docs.suricata.io/en/latest/install.html) for the supported repository and package instructions for your distribution. Do not add a repository intended for a different Debian/Ubuntu release.

---

## Install

Clone the repository and enter its directory:

```bash
git clone https://github.com/x0xr00t/sl0ppy-SuriDash.git
cd sl0ppy-SuriDash
```

Make the dashboard executable:

```bash
chmod +x ./sl0ppy-SuriDash
```

If your checkout uses another script filename, substitute that filename in the commands below.

---

## Identify interfaces and IP networks

Do not copy interface names or example addresses blindly. Discover the actual interface names and address ranges on the machine that will run Suricata.

```bash
ip -br link
ip -br -4 address
ip -br -6 address
ip route
ip -6 route
```

Inspect one interface in detail:

```bash
ip -details link show dev enp3s0
ip -4 address show dev enp3s0
ip -6 address show dev enp3s0
```

Replace `enp3s0` with your real interface name.

### Example address plan

The following is documentation-only example data. Use your actual LAN prefix, not these sample values, unless they match your network.

| Purpose | Example |
|---|---|
| LAN IPv4 network | `192.168.x.x/24` |
| Router IPv4 address | `192.168.x.254` |
| Sensor IPv4 address | `192.168.x.10` |
| LAN IPv6 prefix | `2001:xxx:xxxx:1::/64` |
| Sensor IPv6 address | `2001:xxx:xxxx:1::10` |

`2001:db8::/32` is reserved for documentation. Replace it with your real IPv6 prefix before deployment.

### Correct HOME_NET examples

For one IPv4 LAN:

```yaml
vars:
  address-groups:
    HOME_NET: "[192.168.x.0/24]"
    EXTERNAL_NET: "!$HOME_NET"
```

For a dual-stack LAN:

```yaml
vars:
  address-groups:
    HOME_NET: "[192.168.x.0/24, 2001:db8:1234:1::/64]"
    EXTERNAL_NET: "!$HOME_NET"
```

For multiple internal networks:

```yaml
vars:
  address-groups:
    HOME_NET: "[192.168.x.0/24, 192.168.x.0/24, 10.20.0.0/16, 2001:xxx:xxxx:1::/64]"
    EXTERNAL_NET: "!$HOME_NET"
```

Important:

- `HOME_NET` is a YAML string containing a Suricata address-group list.
- Use CIDR network prefixes, not a guessed host address.
- Include every internal subnet that the sensor is expected to protect or monitor.
- Do not put public Internet ranges into `HOME_NET`.
- `EXTERNAL_NET: "!$HOME_NET"` means addresses outside the configured home networks.
- If the sensor only monitors one VLAN, set `HOME_NET` to the protected VLAN networks rather than every network in the organization.

---

## Configure Suricata

Edit the existing configuration:

```bash
sudo cp -a /etc/suricata/suricata.yaml \
  "/etc/suricata/suricata.yaml.backup.$(date +%Y%m%d-%H%M%S)"

sudoedit /etc/suricata/suricata.yaml
```

Suricata's YAML file contains many sections. **Merge the following settings into the existing sections. Do not append duplicate top-level keys** such as `vars`, `outputs`, `stats`, or `af-packet`.

### Rule paths

A common Debian/Kali/Ubuntu package layout is:

```yaml
default-rule-path: /var/lib/suricata/rules

rule-files:
  - suricata.rules
```

Use the actual rule filename installed by `suricata-update`. Check it with:

```bash
sudo find /var/lib/suricata/rules -maxdepth 1 -type f -name '*.rules' -print
```

If your installation uses a different rule directory or filename, keep the package's working values.

### Statistics

Merge into the existing `stats` section:

```yaml
stats:
  enabled: yes
  interval: 2
```

A two-second interval gives the dashboard relatively frequent counter updates. It can increase logging/processing overhead slightly; use a longer interval on constrained systems if needed.

### EVE and fast output

Merge the required event types into the existing `outputs` list. Do not create a second `outputs` key.

```yaml
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert
        - anomaly
        - dns
        - http
        - tls
        - flow
        - stats

  - fast:
      enabled: yes
      filename: fast.log
```

Notes:

- EVE output is structured JSON and is the preferred source for event analysis.
- The `flow` event type is singular.
- `stats` in EVE is useful when you want statistics in the event log. Suricata's global `stats` section controls the interval.
- Retain any other output types your deployment already needs.
- `filename` is relative to Suricata's `default-log-dir` unless an absolute path is configured.

A typical log directory is:

```yaml
default-log-dir: /var/log/suricata
```

Confirm the effective log directory in your installed configuration.

---

## Configure the command socket

SuriDash needs access to Suricata's Unix command socket for runtime information.

In the existing `suricata.yaml`, enable the socket:

```yaml
unix-command:
  enabled: yes
  # filename is optional; if set, it is relative to Suricata's local state base directory
  filename: suricata-command.socket
```

Do not assume the socket is always `/run/suricata/` or `/var/run/suricata/`. The actual location depends on the package, service configuration, and Suricata local-state directory.

Find the live socket:

```bash
sudo find /run /var/run /var/lib/suricata \
  -type s -name '*suricata*.socket' -o -type s -name 'suricata-command.socket' \
  2>/dev/null
```

If the `find` expression is ambiguous on your system, use:

```bash
sudo find /run /var/run /var/lib/suricata \
  -type s -name 'suricata-command.socket' 2>/dev/null
```

Test the socket using the discovered path:

```bash
sudo suricatasc -s /run/suricata/suricata-command.socket -c version
```

Replace the example path with the path returned by `find`.

If your `suricatasc` build does not accept `-s`, inspect its syntax:

```bash
suricatasc --help
```

The socket must exist and be accessible to the account running the client. Do not make it world-writable. Prefer running the dashboard with the required privileges or granting access through a controlled group/service arrangement.

---

## Install and update rules

Fetch the configured rule sources:

```bash
sudo suricata-update
```

List available sources:

```bash
sudo suricata-update list-sources
```

Enable the Emerging Threats Open rules source if it is not already enabled:

```bash
sudo suricata-update --enable-source et/open
sudo suricata-update
```

Source names can vary with `suricata-update` versions. Check `list-sources` and use the exact source identifier shown by your installed version. Do not use `etpro/etopen` as a generic replacement for the community `et/open` source.

Check that rules were written:

```bash
sudo find /var/lib/suricata/rules -maxdepth 1 -type f -name '*.rules' -ls
```

Rule updates should be scheduled and monitored. An update command succeeding does not prove that every rule is appropriate for your network.

---

## Validate and start Suricata

Always test the configuration before restarting the service:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml
```

Proceed only if the configuration test completes successfully.

Start and enable the packaged service:

```bash
sudo systemctl enable --now suricata
sudo systemctl status suricata --no-pager
```

Inspect recent logs:

```bash
sudo journalctl -u suricata -n 100 --no-pager
```

If the service is not managed by systemd on your distribution, use its service manager and package documentation.

---

## IDS mode: passive monitoring

IDS is the recommended starting point. It observes traffic and generates alerts but does not sit inline to block packets.

For a simple Linux interface capture, configure the existing `af-packet` section for the actual monitoring interface:

```yaml
af-packet:
  - interface: enp3s0
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes
```

Replace `enp3s0` with the interface carrying the traffic you are authorized to monitor.

For a sensor connected to a switch mirror/SPAN port, configure the switch mirror correctly. A normal access port does not automatically expose all LAN traffic.

Validate and restart:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml
sudo systemctl restart suricata
```

Check events:

```bash
sudo tail -F /var/log/suricata/eve.json
```

Show alerts only:

```bash
sudo jq -c 'select(.event_type == "alert")' \
  /var/log/suricata/eve.json
```

IDS mode does not require NFQUEUE firewall rules or an AF_PACKET `copy-iface` pair.

---

## IPS mode A: AF_PACKET inline bridge

<badge color="warning">Requires two dedicated network interfaces</badge>

AF_PACKET IPS is a Layer-2 inline design. Suricata receives traffic on one interface and forwards it through the paired interface. It does not require iptables or nftables NFQUEUE rules.

Use this design when the Linux machine is physically placed between two network segments, for example:

```text
Internet / upstream
        |
     [eth0]
        |
  +------------------+
  | Linux + Suricata |
  | AF_PACKET IPS    |
  +------------------+
        |
     [eth1]
        |
 LAN / downstream
```

The interface names below are examples. Confirm the actual physical ports before applying this configuration.

### AF_PACKET configuration

Merge this into the existing `af-packet` section:

```yaml
af-packet:
  - interface: eth0
    threads: 1
    cluster-id: 98
    cluster-type: cluster_flow
    defrag: no
    copy-mode: ips
    copy-iface: eth1
    buffer-size: 64535

  - interface: eth1
    threads: 1
    cluster-id: 97
    cluster-type: cluster_flow
    defrag: no
    copy-mode: ips
    copy-iface: eth0
    buffer-size: 64535
```

The pairing must be symmetric:

- `eth0` copies to `eth1`.
- `eth1` copies to `eth0`.
- The two interfaces must have different `cluster-id` values.
- Both interfaces must be dedicated to the inline path.
- Keep the same MTU on both interfaces.
- Start with one thread per interface; tune only after measuring performance.

Do not copy the old example's `ring-size: 200000`, `tpacket-v3: yes`, or `topo-gso: yes` blindly. Large rings can consume substantial memory, and capture/offload settings are hardware- and version-dependent. The documented minimal IPS configuration is a safer baseline.

### Inline stream handling

In the existing stream configuration, ensure inline mode is enabled:

```yaml
stream:
  inline: auto
```

Use `yes` only when you specifically intend to force inline stream handling and have validated the behavior for your Suricata version.

### Bring up the interfaces

For a transparent Layer-2 inline pair, the interfaces normally do not need IP addresses:

```bash
sudo ip link set dev eth0 up
sudo ip link set dev eth1 up

ip -br link show eth0
ip -br link show eth1
```

Do not remove addresses from interfaces remotely if one of them is your active management connection. Plan the physical cabling and out-of-band recovery first.

Check and align MTU:

```bash
ip link show dev eth0
ip link show dev eth1
```

Both links must use compatible MTU settings. Also review NIC offloads where applicable; GRO, LRO, or TSO behavior can cause oversized frames that the inline transmit path cannot forward correctly. Change offload settings only after checking driver support and measuring the result.

### Validate and start AF_PACKET IPS

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml
```

After validation, use the package's service configuration to start Suricata with the AF_PACKET interfaces configured in YAML. If testing manually, stop the service first to avoid two Suricata processes opening the same interfaces:

```bash
sudo systemctl stop suricata
sudo suricata -c /etc/suricata/suricata.yaml \
  --af-packet=eth0 --af-packet=eth1
```

This runs in the foreground. Stop it with `Ctrl+C` after testing. Do not leave a production inline path without a managed service and a tested recovery plan.

**Important:** AF_PACKET IPS is not a normal one-interface IDS capture. Do not configure the same interface as both passive IDS and inline IPS in conflicting AF_PACKET entries. Suricata rejects mixed AF_PACKET IPS and IDS/TAP configurations because the behavior is undefined.

---

## IPS mode B: NFQUEUE inline filtering

<badge color="warning">Firewall rules can interrupt network connectivity</badge>

NFQUEUE is a Netfilter inline design. Linux firewall rules send selected packets to a queue, and Suricata reads that queue using `-q`.

Unlike AF_PACKET bridge mode, NFQUEUE does not require a pair of physical interfaces. It is commonly used on a Linux router or firewall.

**Choose one firewall example below. Do not install both iptables and nftables rules for the same traffic path unless you deliberately designed that combined ruleset.**

### Option 1: iptables for routed traffic

For a Linux router forwarding traffic between `eth0` and `eth1`, use the `FORWARD` chain. This example sends IPv4 TCP and UDP packets in both directions to queue 0:

```bash
sudo iptables -I FORWARD 1 -i eth0 -o eth1 -p tcp \
  -j NFQUEUE --queue-num 0

sudo iptables -I FORWARD 1 -i eth0 -o eth1 -p udp \
  -j NFQUEUE --queue-num 0

sudo iptables -I FORWARD 1 -i eth1 -o eth0 -p tcp \
  -j NFQUEUE --queue-num 0

sudo iptables -I FORWARD 1 -i eth1 -o eth0 -p udp \
  -j NFQUEUE --queue-num 0
```

Replace `eth0` and `eth1` with the real ingress and egress interfaces. If you intend to inspect all forwarded IP protocols, omit the `-p tcp` and `-p udp` selectors, but understand the resulting traffic volume and test it first.

For IPv6, create equivalent rules with `ip6tables`:

```bash
sudo ip6tables -I FORWARD 1 -i eth0 -o eth1 \
  -j NFQUEUE --queue-num 0

sudo ip6tables -I FORWARD 1 -i eth1 -o eth0 \
  -j NFQUEUE --queue-num 0
```

These are examples for a routed gateway. They are not a universal replacement for a host firewall policy.

### Option 2: iptables for traffic to and from the Linux host

Only use `INPUT` and `OUTPUT` when you intentionally want to inspect traffic destined for or generated by the local machine. Do not use these rules as a substitute for a router's `FORWARD` path.

Example for local IPv4 TCP traffic:

```bash
sudo iptables -I INPUT 1 -p tcp \
  -j NFQUEUE --queue-num 0

sudo iptables -I OUTPUT 1 -p tcp \
  -j NFQUEUE --queue-num 0
```

This example intentionally queues only TCP. Add other protocols only when required and tested. Exclude loopback and management traffic if your policy requires it; make sure you do not create a queueing loop or lock yourself out.

### Start Suricata on the matching queue

The queue number in the firewall rule and Suricata command must match:

```bash
sudo suricata -c /etc/suricata/suricata.yaml -q 0
```

For a persistent deployment, configure the Suricata service to start with `-q 0` using a distribution-appropriate systemd override or service configuration. Do not run a second manual instance while the packaged service is already active.

Check the installed command-line options:

```bash
suricata --help | grep -A2 -B2 -- '-q'
```

For multiple queues, Suricata must be started with every queue ID, for example:

```bash
sudo suricata -c /etc/suricata/suricata.yaml -q 0 -q 1
```

The firewall must send traffic to those same queue IDs. Do not configure a queue range and assume Suricata will automatically consume every queue.

### Option 3: nftables for routed traffic

Use this alternative if your firewall is managed with nftables. This creates a dedicated forward hook chain and queues only traffic crossing the named interfaces:

```bash
sudo nft add table inet suricata
sudo nft 'add chain inet suricata forward { type filter hook forward priority 10; policy accept; }'

sudo nft add rule inet suricata forward iifname "eth0" oifname "eth1" queue num 0
sudo nft add rule inet suricata forward iifname "eth1" oifname "eth0" queue num 0
```

Start Suricata with the same queue:

```bash
sudo suricata -c /etc/suricata/suricata.yaml -q 0
```

The `inet` family covers IPv4 and IPv6. Review the complete nftables ruleset and hook priorities before deployment:

```bash
sudo nft list ruleset
```

#### NFQUEUE bypass behavior

You may see examples using `--queue-bypass` with iptables or `queue ... bypass` with nftables. Bypass allows packets to continue when no userspace queue listener is present. This can preserve connectivity during a Suricata outage, but it also means IPS inspection and blocking are absent during that outage.

Without bypass, packets sent to a queue with no listener can be dropped. Choose the failure behavior deliberately; neither setting is a substitute for service monitoring and a recovery plan.

---

## Verify traffic and blocking

### Verify Suricata is running

```bash
sudo systemctl status suricata --no-pager
sudo journalctl -u suricata -n 100 --no-pager
```

### Verify the command socket

Find the socket:

```bash
sudo find /run /var/run /var/lib/suricata \
  -type s -name 'suricata-command.socket' 2>/dev/null
```

Use the actual path:

```bash
sudo suricatasc -s /run/suricata/suricata-command.socket -c version
```

### Verify EVE output

```bash
sudo test -s /var/log/suricata/eve.json && echo "EVE log exists"
sudo tail -F /var/log/suricata/eve.json
```

Count recent alert events:

```bash
sudo jq -c 'select(.event_type == "alert")' \
  /var/log/suricata/eve.json | tail
```

### Verify NFQUEUE counters

For iptables:

```bash
sudo iptables -vnL FORWARD --line-numbers
sudo ip6tables -vnL FORWARD --line-numbers
```

For nftables:

```bash
sudo nft -a list table inet suricata
```

Packet counters should increase when matching traffic crosses the configured path. A rule existing in the firewall does not prove Suricata is consuming the queue.

### Verify AF_PACKET interfaces

```bash
ip -s link show dev eth0
ip -s link show dev eth1
```

Check Suricata logs for AF_PACKET startup errors and inspect EVE statistics for capture drops. A running process alone does not prove that packets are successfully traversing both interfaces.

### Test safely

Use a controlled test host and a test rule in a lab or maintenance window. Confirm all of the following independently:

1. Traffic reaches the expected sensor interface or NFQUEUE rule.
2. Suricata processes the traffic.
3. EVE records the expected event.
4. A test `drop` rule blocks only the intended test traffic in IPS mode.
5. Normal management and application traffic still works.
6. The system recovers correctly after a Suricata restart or failure.

Do not test blocking against third-party systems without authorization.

---

## Run SuriDash

Once Suricata is running and the command socket and logs are available:

```bash
sudo bash ./sl0ppy-SuriDash
```

If the file has its executable bit set:

```bash
sudo ./sl0ppy-SuriDash
```

The dashboard is a monitor. It does not enable AF_PACKET IPS, start NFQUEUE mode, or add firewall rules.

### Usage

```text
Usage: sudo ./sl0ppy-SuriDash [options]

  -i, --interval SEC    Refresh interval in seconds
      --once            Print one frame and exit
      --check           List counters and the statistics keys they resolved from
      --debug-counters  Dump numeric statistics keys exposed by Suricata
  -V, --version         Print version
  -h, --help            Show help

Keys:
  q                    Quit
  p                    Pause
  r                    Refresh now
  j/k or arrows        Scroll
  PgUp/PgDn            Page up/down
  space/b              Page
  g                    Top
  G                    Bottom
```

The exact default refresh interval is determined by the checked-out SuriDash script.

Useful diagnostics:

```bash
sudo ./sl0ppy-SuriDash --check
sudo ./sl0ppy-SuriDash --once
sudo ./sl0ppy-SuriDash --debug-counters
```

If the script is named differently, replace the executable name accordingly.

---

## Docker

Docker deployment depends on the repository's actual Compose file, Dockerfile, entrypoint, mounted Suricata configuration, and privileges. The following commands apply only if the checkout contains a working `compose.yaml` or `docker-compose.yml` with services named `suricata` and `suridash`.

```bash
docker compose config
docker compose build
docker compose up -d suricata
docker compose logs -f suricata
```

Run the dashboard container:

```bash
docker compose run --rm suridash
```

If the image entrypoint forwards arguments to SuriDash:

```bash
docker compose run --rm suridash --check
```

Before using Docker for IPS:

- NFQUEUE requires access to the host's Netfilter queue path and suitable privileges.
- AF_PACKET requires access to the host network interfaces and suitable capabilities/privileges.
- A container network namespace does not automatically see or control the host's physical traffic.
- Do not use `privileged: true` as a reflex; grant only the capabilities and devices actually required.
- Confirm that the command socket and log files are mounted read-only where possible.
- Validate the container's effective interfaces, routes, socket path, and log paths before relying on its dashboard.

The Docker commands above are not a substitute for checking the repository's Compose definitions.

---

## Troubleshooting

### Socket not found

```bash
sudo find /run /var/run /var/lib/suricata \
  -type s -name 'suricata-command.socket' 2>/dev/null

sudo journalctl -u suricata -n 100 --no-pager
```

Check `unix-command.enabled`, the local-state directory, and the actual socket filename. The socket filename is relative to Suricata's local-state base directory unless overridden.

### `suricatasc` cannot connect

- Confirm Suricata is running.
- Confirm the socket exists.
- Use the exact socket path with the `suricatasc -s` option supported by your installed build.
- Check permissions; do not make the socket world-writable.
- Check whether another Suricata instance is using a different configuration or socket.

### No alerts appear

No alerts does not necessarily mean the sensor is broken. Check:

```bash
sudo jq -c 'select(.event_type == "stats")' \
  /var/log/suricata/eve.json | tail

sudo tail -n 100 /var/log/suricata/suricata.log
sudo suricata-update
```

Confirm that the sensor sees the relevant traffic, the rules are loaded, and the traffic matches enabled signatures.

### NFQUEUE traffic stops

If Suricata is not listening on the configured queue, queued packets may be dropped unless queue bypass is configured. Restore the traffic path using your pre-tested rollback procedure. Confirm the queue ID in both the firewall and Suricata command line.

### AF_PACKET traffic stops

Check:

- Correct physical cabling and interface pairing.
- Both interfaces are up.
- Both interfaces have matching MTU.
- Distinct cluster IDs.
- Symmetric `copy-mode: ips` and `copy-iface` settings.
- Suricata startup logs and NIC driver/offload compatibility.

### Dashboard shows missing or zero counters

Run:

```bash
sudo ./sl0ppy-SuriDash --check
sudo suricatasc -s /path/to/actual/socket -c version
```

Replace the socket path. A zero counter can mean no matching traffic, a counter-name difference between Suricata versions, or a mapping issue. Use `--check` and `--debug-counters` to distinguish these cases.

### YAML validation fails

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml -v
```

Common causes include duplicate top-level YAML keys, incorrect indentation, an invalid interface name, a misspelled setting, or a rule file that does not exist. Merge configuration snippets into the existing sections instead of pasting duplicate sections at the end of the file.

---

## Safe rollback

**Keep local console or out-of-band access available before changing an inline firewall.** Do not flush all firewall rules on a remote machine: that can remove unrelated security policy and expose services.

### Remove only the example iptables NFQUEUE rules

For the routed IPv4 example:

```bash
sudo iptables -D FORWARD -i eth0 -o eth1 -p tcp -j NFQUEUE --queue-num 0
sudo iptables -D FORWARD -i eth0 -o eth1 -p udp -j NFQUEUE --queue-num 0
sudo iptables -D FORWARD -i eth1 -o eth0 -p tcp -j NFQUEUE --queue-num 0
sudo iptables -D FORWARD -i eth1 -o eth0 -p udp -j NFQUEUE --queue-num 0
```

For the IPv6 example:

```bash
sudo ip6tables -D FORWARD -i eth0 -o eth1 -j NFQUEUE --queue-num 0
sudo ip6tables -D FORWARD -i eth1 -o eth0 -j NFQUEUE --queue-num 0
```

If you installed the local-host `INPUT`/`OUTPUT` example, remove those exact rules instead. If a command reports that the rule does not exist, inspect the active ruleset and do not delete unrelated rules.

### Remove only the example nftables table

```bash
sudo nft delete table inet suricata
```

This removes the dedicated example table only. Do not run it if you put unrelated rules in that table.

### Restore AF_PACKET IDS/passive operation

1. Stop the inline Suricata service.
2. Restore the backed-up YAML or replace the paired IPS entries with a tested passive IDS capture configuration.
3. Restore the intended network topology and cabling.
4. Run the Suricata configuration test.
5. Start the service and verify traffic and logs.

Do not simply remove `copy-iface` from a live bridge and assume the network will continue forwarding.

---

## Operational notes

- Start with IDS mode and verify visibility before enabling inline blocking.
- AF_PACKET IPS requires two dedicated interfaces and a deliberate physical network path.
- NFQUEUE requires firewall rules and a Suricata process consuming the matching queue ID.
- Do not configure AF_PACKET IPS and NFQUEUE for the same traffic path without a carefully designed architecture.
- The dashboard is read-only; its health score is an operational heuristic, not proof that the sensor sees every packet.
- Tune capture threads, queue count, ring sizes, and NIC offloads only after measuring packet rate, CPU usage, drops, and latency.
- Keep Suricata, rules, and the dashboard updated.
- Test changes in a lab or maintenance window and retain a known-good configuration and recovery path.

## References

- [Suricata User Guide](https://docs.suricata.io/en/latest/)
- [Suricata IPS / inline for Linux](https://docs.suricata.io/en/latest/ips/setting-up-ipsinline-for-linux.html)
- [Suricata Unix socket](https://docs.suricata.io/en/latest/unix-socket.html)
- [Suricata command-line options](https://docs.suricata.io/en/latest/command-line-options.html)
- [Suricata installation guide](https://docs.suricata.io/en/latest/install.html)

---

**Built for defenders.**

**x0xr00t — Patrick Hoogeveen**  
**Team sl0ppyr00t**
