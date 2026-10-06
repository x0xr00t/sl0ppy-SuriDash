# SuriDash / Suricata image
# Debian-based, contains: suricata (engine), suricatasc, jq, the dashboard deps.
FROM debian:bookworm-slim

ARG SURIDASH_VERSION=v1.1

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        suricata \
        jq \
        python3 \
        mawk \
        sed \
        coreutils \
        ncurses-bin \
        grep \
        findutils \
        procps \
        tini \
    && rm -rf /var/lib/apt/lists/*

# sanity: bash >= 4 is required by the dashboard
RUN bash -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]'

WORKDIR /opt/suridash

# Drop the dashboard script next to the image
COPY suridash.sh /opt/suridash/suridash.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /opt/suridash/suridash.sh /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/log/suricata /run/suricata /var/lib/suricata/rules

# run as root: the script requires root (socket + log access)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["suridash"]
