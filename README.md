![GitHub release](https://img.shields.io/github/v/release/x0xr00t/sl0ppy-SuriDash)
![GitHub license](https://img.shields.io/github/license/x0xr00t/sl0ppy-SuriDash)
![GitHub stars](https://img.shields.io/github/stars/x0xr00t/sl0ppy-SuriDash)
![GitHub issues](https://img.shields.io/github/issues/x0xr00t/sl0ppy-SuriDash)
# sl0ppy-SuriDash
Sl0ppy-SuriDash is a bash based dashboard for suricata in IDS or IPS Mode

# change log v1.5.1
```
v1.5.1 changes (health penalty fixes, on top of v1.5):
#   * CAPTURE-DROP PENALTY SOFTENED: a single dropped packet (e.g. one lost
#     ICMP ping) in one stats window no longer slams the health score.
#     - Dead-zone: drop windows below 0.5% cost 0 points (LAN noise).
#     - Weight halved: 3 points per full percent instead of 6, cap 30 kept.
#     - Two-tick rule: the penalty only fires after two CONSECUTIVE windows
#       with drops - one bad tick is ignored, sustained drops still show.
#   * COSMETIC PENALTIES REDUCED: frag-timeouts and bad-checksums now cost
#     1 point each instead of 2 (normal ICMP / offload noise on a LAN).
#   * BUGFIX: penalty reasons are now appended to "reasons" (the loop used
#     the misspelled variable "reason", so the Reasons: line never listed
#     the active penalties - you could not see WHY the score was ~70%).
```

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
    HOME_NET: "[192.168.x.x/24]"      # your LAN
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
# For ITV IPTV in IPS MODE add this under HOMENET 
* kpn uptv itv example
```
    KPN_STB: ""
    
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


## af-packet block exaple ips 

```
af-packet:
  - interface: eth0
    # Number of receive threads. "auto" uses the number of cores
    #threads: auto
    # Default clusterid. AF_PACKET will load balance packets based on flow.
    cluster-id: 99
    # Default AF_PACKET cluster type. AF_PACKET can load balance per flow or per hash.
    # This is only supported for Linux kernel > 3.1
    # possible value are:
    #  * cluster_flow: all packets of a given flow are sent to the same socket
    #  * cluster_cpu: all packets treated in kernel by a CPU are sent to the same socket
    #  * cluster_qm: all packets linked by network card to a RSS queue are sent to the same
    #  socket. Requires at least Linux 3.14.
    #  * cluster_ebpf: eBPF file load balancing. See doc/userguide/capture-hardware/ebpf-xdp.rst for
    #  more info.
    # Recommended modes are cluster_flow on most boxes and cluster_cpu or cluster_qm on system
    # with capture card using RSS (requires cpu affinity tuning and system IRQ tuning)
    # cluster_rollover has been deprecated; if used, it'll be replaced with cluster_flow.
    cluster-type: cluster_flow
    # In some fragmentation cases, the hash can not be computed. If "defrag" is set
    # to yes, the kernel will do the needed defragmentation before sending the packets.
    #defrag: yes
    # Lock memory map to avoid it being swapped. Be careful that over
    # subscribing could lock your system
    #mmap-locked: yes
    # Use tpacket_v3 capture mode.
    # Defaults to true for non-copy modes, and false for tap and ips mode.
    # Don't use it in IPS or TAP mode as it causes severe latency.
    #tpacket-v3: yes
    # Ring size will be computed with respect to "max-pending-packets" and number
    # of threads. You can set manually the ring size in number of packets by setting
    # the following value. If you are using flow "cluster-type" and have really network
    # intensive single-flow you may want to set the "ring-size" independently of the number
    # of threads:
    #ring-size: 2048
    # Block size is used by tpacket_v3 only. It should set to a value high enough to contain
    # a decent number of packets. Size is in bytes so please consider your MTU. It should be
    # a power of 2 and it must be multiple of page size (usually 4096).
    #block-size: 32768
    # tpacket_v3 block timeout: an open block is passed to userspace if it is not
    # filled after block-timeout milliseconds.
    #block-timeout: 10
    # Block size for tpacket-v2. In 7.0.9 the built-in default was
    # increased from 32768 to 131072. Uncomment and reset back to
    # 32768 if this is a problem with your configuration.
    #v2-block-size: 131072
    # On busy systems, set it to yes to help recover from a packet drop
    # phase. This will result in some packets (at max a ring flush) not being inspected.
    #use-emergency-flush: yes
    # recv buffer size, increased value could improve performance
    # buffer-size: 32768
    # Set to yes to disable promiscuous mode
    # disable-promisc: no
    # Choose checksum verification mode for the interface. At the moment
    # of the capture, some packets may have an invalid checksum due to
    # the checksum computation being offloaded to the network card.
    # Possible values are:
    #  - kernel: use indication sent by kernel for each packet (default)
    #  - yes: checksum validation is forced
    #  - no: checksum validation is disabled
    #  - auto: Suricata uses a statistical approach to detect when
    #  checksum off-loading is used.
    # Warning: 'capture.checksum-validation' must be set to yes to have any validation
    #checksum-checks: kernel
    # BPF filter to apply to this interface. The pcap filter syntax applies here.
    #bpf-filter: port 80 or udp
    # You can use the following variables to activate AF_PACKET tap or IPS mode.
    # If copy-mode is set to ips or tap, the traffic coming to the current
    # interface will be copied to the copy-iface interface. If 'tap' is set, the
    # copy is complete. If 'ips' is set, the packet matching a 'drop' action
    # will not be copied.
    #copy-mode: ips
    #copy-iface: eth1
    #  For eBPF and XDP setup including bypass, filter and load balancing, please
    #  see doc/userguide/capture-hardware/ebpf-xdp.rst for more info.
    # Disable HW timestamp support. HW timestamps can be unreliable, see
    # https://redmine.openinfosecfoundation.org/issues/7585
    #disable-hwtimestamp: false
    defrag: yes
    use-mmap: yes                  # Enables zero-copy memory ring
    mmap-locked: yes               # Prevents kernel from swapping memory to disk (huge jitter cause)
    ring-size: 200000              # Drastically expands packet capacity
    block-size: 32768
    tpacket-v3: yes    
    topo-gso: yes
    copy-mode: ips
    copy-iface: eth1

    interface: eth1
    cluster-id: 98
    cluster-type: cluster_flow
    topo-gso: yes
    defrag: yes
    use-mmap: yes                  # Enables zero-copy memory ring
    mmap-locked: yes               # Prevents kernel from swapping memory to disk (huge jitter cause)
    ring-size: 200000              # Drastically expands packet capacity
    block-size: 32768
    tpacket-v3: yes
    copy-mode: ips
    copy-iface: eth0
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
