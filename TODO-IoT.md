# TODO — IoT and home-network telemetry

Bring the home network's devices and services into the Elastic stack:
Home Assistant, the TP-Link Deco mesh, CoreDNS, Pi-hole, the QNAP TS-230,
a syslog path through Logstash for anything without its own
integration, and SNMP polling for devices that speak it.

**Prefer Elastic-supported integrations** (Fleet packages on an Elastic
Agent) over hand-written pipelines: they bring parsing, ECS mapping and
dashboards. A custom Logstash pipeline is the fallback for sources with no
package.

Related work lives elsewhere:

- WSL terminal and AI agent command logs into Elastic:
  [`TODO-SRE-AI.md`](TODO-SRE-AI.md) A2 ("Command audit trail").
- Fleet agents on core's `proxy`/`server01`, CoreDNS and Caddy metrics:
  [`TODO-SRE-AI.md`](TODO-SRE-AI.md) A9 ("Telemetry coverage"). The
  CoreDNS and Caddy steps below cover the same items.

## What's possible, per source

| Source | Where | Supported Elastic route | Verdict |
| --- | --- | --- | --- |
| QNAP TS-230 | NAS | `qnap_nas` 1.26.0 (GA), syslog over TCP/UDP to an agent | Yes, supported |
| CoreDNS `ns1` | `server01`, macvlan `192.168.68.2` | `coredns` 0.10.0 (beta, logs) + `prometheus` 1.24.4 for `:9153` | Yes |
| CoreDNS `ns2` | QNAP Container Station, `.3` | Prometheus scrape of `:9153`; logs have no route yet | Metrics only |
| Home Assistant | HAOS on a Raspberry Pi 3, `192.168.68.11` | `prometheus` (HA's `/api/prometheus`), or the community `homeassistant-elasticsearch` component | Yes, metrics/states. **No logs** (HAOS has no remote syslog) |
| TP-Link Deco | mesh Wi-Fi | No Elastic package; most Deco firmware has no remote syslog. Via HA's community `tplink_deco` component | Through HA only |
| Pi-hole `.5` / `.6` | `server01` / QNAP | No Elastic package | Custom only; candidate to skip |
| Caddy | `proxy` | No Elastic package; Caddy metrics via `prometheus` | Optional, see Step 7 |
| SNMP devices (QNAP, others) | LAN | No Elastic package. EDOT Collector `snmpreceiver` (Extended, EDOT 9.3+) or Logstash's bundled `snmp`/`snmptrap` inputs | Yes, see Step 8 |
| Proxmox `pve1` | host | `system` (already in place). The [Proxmox blog post](https://www.elastic.co/observability-labs/blog/monitoring-proxmox-ve-with-elastic) uses just one agent on the host plus Universal Profiling; it uses no Proxmox API or syslog input | Nothing new to add |

Package versions are checked against Kibana 9.5.4 in the Elastic package
registry (`epr.elastic.co`) on 2026-10-08.

## Step 0 — Decisions before building

- [ ] **Policy layout for core.** `proxy` and `server01` share the
      `homelab-core` policy, so a Prometheus scrape added there would run
      on both hosts and collect everything twice. Pick one:
      - split into per-VM policies (`homelab-proxy`, `homelab-dns`), or
      - keep one policy and add `${host.name} == "proxy"` conditions to
        the scrape inputs.

      Per-VM policies are easier to read in Fleet and need no conditions.
- [ ] **Where scrapes run.** CoreDNS `ns1` sits on `server01`'s macvlan
      and `server01` itself can't reach it (macvlan isolates a host from
      its own containers). Scrape from `proxy` (or from the ingest VM).
- [ ] **HA data path**: Prometheus scrape (Step 3a) or the
      `homeassistant-elasticsearch` component (Step 3b). See Step 3 for
      the trade-off.

## Step 1 — Syslog on the ingest VM

The ingest VM (`192.168.68.34`) receives every device's syslog. Two
listeners, on different ports:

- [ ] **QNAP via Elastic Agent** (supported route). Add the `qnap_nas`
      integration to the `logstash` agent policy
      (`stacks/elastic/fleet`), TCP input, `syslog_host: 0.0.0.0`,
      `syslog_port: 9301` (package default), `tz_offset` set to the NAS's
      timezone. Data reaches Elasticsearch through the existing Logstash
      output, like every other agent.
- [ ] **Catch-all Logstash syslog pipeline** for devices with no
      integration (`roles/logstash`):
      - new `syslog` pipeline in `pipelines.yml.j2`
        (`conf.d/syslog.conf`), persisted queue like `elastic-agent`
      - `syslog` input (or `tcp`/`udp` + `syslog_pri`/grok) on
        `5514/tcp` and `5514/udp` (non-privileged, Logstash runs as
        non-root)
      - ECS output: `data_stream_type => logs`,
        `data_stream_dataset => syslog.<source>` (set from the sender's
        IP via a lookup table, e.g. `deco`, `misc`),
        `data_stream_namespace => default`
      - `logstash_writer` can already create `logs-syslog.*-*`: its role
        (`roles/logstash/defaults/main.yml`) covers `logs-*-*`
      - new `group_vars/logstash.yml` vars: `logstash_syslog_port`, the
        IP-to-source map
- [ ] Firewall: the VMs run no host firewall, so nothing to open there.
      Check Proxmox's firewall isn't enabled for the ingest VM; if it is,
      or one is added later, allow both ports from `192.168.68.0/22` only.
- [ ] Alternative for the catch-all: the `syslog_router` package (1.0.1,
      GA) on the agent instead of Logstash. It routes one syslog listener
      to several integrations by matching the message. Worth it only if
      more integration-backed devices appear later.
- [ ] Healthcheck (`99-healthcheck.yml`): `logger -n 192.168.68.34 -P 5514`
      from a VM, then a search finds the line.

## Step 2 — QNAP TS-230

- [ ] QTS: **QuLog Center → Log Sender**, add `192.168.68.34`, TCP,
      port `9301`, send system event and access logs.
- [ ] Confirm the `qnap_nas` dashboards fill in Kibana.
- [ ] Container Station containers (CoreDNS `ns2`, Pi-hole `.6`) don't
      log through QuLog. Their logs stay out of scope unless an agent runs
      on the NAS (TODO-SRE-AI A9 tracks that decision).
- [ ] Disk, volume, fan and temperature health: SNMP, Step 8.

## Step 3 — Home Assistant (Raspberry Pi 3)

HAOS supports a Pi 3 only with the **64-bit image** (`rpi3-64`). 32-bit
images lost support in 2025.12
([HA blog](https://home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/)).

- [ ] Check **Settings → System → Repairs/About** shows `aarch64`. If it
      says `armv7`, reinstall from Raspberry Pi Imager with the 64-bit
      image and restore a backup.

### 3a. Prometheus scrape (supported route)

- [ ] HA `configuration.yaml`: enable `prometheus:` (with
      `filter:` to limit which entities are exported).
- [ ] Create a long-lived access token for a dedicated HA user
      (`elastic-scraper`), store it in core's SOPS file, write it
      root-only on `proxy` (e.g. `/etc/elastic-agent/ha-token`).
- [ ] `prometheus` 1.24.4 integration on `proxy`'s policy: host
      `192.168.68.11:8123` (or `ha.homelab.bcochofel.com` through Caddy),
      path `/api/prometheus`, `bearer_token_file`, 60s period.
- [ ] Limit: Prometheus exports numeric **states**; most **attributes**
      (e.g. Deco per-client bandwidth) are missing.

### 3b. `homeassistant-elasticsearch` component (community)

[legrego/homeassistant-elasticsearch](https://github.com/legrego/homeassistant-elasticsearch),
installed through HACS. It writes states and attributes into
`metrics-homeassistant.*` TSDS data streams through the Bulk API.

- Needs Elasticsearch 8.14+ (fine with 9.5.4; check its release notes
  name 9.x before installing).
- HA talks **straight to Elasticsearch** (`:9200`), bypassing Logstash.
  This breaks the "all data through Logstash" pattern and needs the
  internal CA (`ansible/pki/elastic-ca.crt`) copied into HA's `/config`.
- API key privileges: cluster `manage_index_templates`, `monitor`;
  indices `metrics-homeassistant.*`: `manage`, `index`, `create_index`,
  `create`. Create the key in `stacks/elastic/cluster`, not by hand.
- Filters by area, device, entity or label; publish interval defaults
  to 60s.
- Not supported by Elastic or Home Assistant.

**Recommendation:** start with 3a. Move to 3b only if Step 4 needs
attributes that Prometheus drops.

## Step 4 — TP-Link Deco mesh (through Home Assistant)

There's no Elastic Deco package, and most Deco firmware has no remote
syslog, so HA is the bridge.

- [ ] Install [amosyuen/ha-tplink-deco](https://github.com/amosyuen/ha-tplink-deco)
      through HACS. Check the Deco model is in its supported list.
- [ ] Log in with the **owner** account (manager accounts don't work).
      Logging into the Deco app/web UI with the owner account logs the
      integration out: make a separate manager account for day-to-day use.
- [ ] What you get: a device tracker per Deco and per client (MAC, IP,
      connection type, band, which Deco it's on,
      `down_kilobytes_per_s`/`up_kilobytes_per_s`), plus Deco CPU and
      memory sensors.
- [ ] Check which of those reach Elastic:
      - Prometheus (3a): CPU/memory sensors and tracker home/away states.
      - Per-client bandwidth and Deco assignment are attributes, so they
        need 3b (or HA template sensors that turn them into states).
- [ ] Optional, firmware-dependent: if the Deco web UI offers a remote
      syslog option, point it at the Step 1 catch-all (`5514`, source
      `deco`).

## Step 5 — CoreDNS

- [ ] Metrics: `prometheus` integration on `proxy`'s policy scraping
      `192.168.68.2:9153` (`ns1`) and `192.168.68.3:9153` (`ns2`).
      Corefile already has `prometheus :9153` in the catch-all block
      (core's `roles/coredns/templates/Corefile.j2`). Check the QNAP
      container publishes `9153`.
- [ ] Logs (`ns1`): `coredns` 0.10.0 (beta) on `server01`'s policy,
      filestream input with the agent's docker provider so
      `${kubernetes.container.id}`-style paths resolve to the CoreDNS
      container. Or keep the `docker` integration already on
      `homelab-core` and add a `coredns` ingest pipeline. Pick one, not
      both.
- [ ] The `log` plugin is only on the `homelab.bcochofel.com` block. Add
      it to `.:53` too if forwarded queries should be logged (high
      volume).

## Step 6 — Pi-hole (optional, no supported integration)

You leaned toward skipping this. Options, if it comes back:

- [ ] Query log: bind-mount the container's `/var/log/pihole/` on
      `server01` and read `pihole.log` with a filestream custom-logs input
      plus a dnsmasq grok pipeline (custom, unsupported).
- [ ] Metrics: a community Prometheus exporter sidecar (Pi-hole v6 API),
      scraped by the `prometheus` integration.
- [ ] Cheapest useful signal: Phase B's DNS SLO probes
      (`TODO-SRE-AI.md`) against `.5`/`.6` from Synthetics or Heartbeat,
      no Pi-hole-side changes at all.

## Step 7 — Caddy (optional, same scrape pattern)

- [ ] Caddyfile: `metrics` global option; scrape `proxy`'s admin
      endpoint with `prometheus` from `proxy`'s policy.
- [ ] Access logs: Caddy JSON logs via the `docker` integration, or a
      file log plus filestream.

## Step 8 — SNMP polling (and traps)

Elastic has no SNMP integration package. Two routes, both on the ingest VM:

- **EDOT Collector `snmpreceiver`**: in EDOT since 9.3.0 as an
  *Extended* component (shipped, but outside Elastic's core support
  tier). The gateway (`roles/edot_gateway`, 9.5.4) already runs on
  ingest and writes to Elasticsearch, so this is a config change. Output
  is real metrics (`metrics-*` data streams). No MIB loading: each metric
  is declared by OID in `otel.yml.j2`. Polling only, no traps.
- **Logstash `snmp` input** (bundled since 8.15 in
  `logstash-integration-snmp`): `get`/`walk`/`tables`, ships the IETF
  MIBs (IF-MIB, HOST-RESOURCES-MIB) and loads vendor MIBs via
  `mib_paths`. Events are documents, not TSDS metrics. Its sibling
  **`snmptrap`** input is the only option here for traps.

**Recommendation:** polling through EDOT `snmpreceiver`, traps (if wanted)
through Logstash `snmptrap`.

Which devices can be polled:

| Device | SNMP? | What's worth polling |
| --- | --- | --- |
| QNAP TS-230 | Yes (v1/v2c/v3, Control Panel → Network & File Services → SNMP) | IF-MIB traffic; QNAP `NAS-MIB`: disk temperature/SMART status, volume free space, fan speed, system temperature. This overlaps `qnap_nas` syslog only for events, not gauges |
| TP-Link Deco | No (no SNMP agent in Deco firmware) | Use Step 4 |
| ISP router / switches | Check each device | IF-MIB interface counters, uptime |
| HAOS, Proxmox, VMs | No `snmpd` on HAOS; VMs and Proxmox already run Elastic Agent | Skip |

- [ ] QNAP: enable SNMP **v3** (`authPriv`, SHA/AES), restrict to the
      ingest VM's IP if QTS allows it. Store the user and passphrases in
      SOPS (`ansible/inventory/group_vars/edot_gateway.sops.yaml` or
      similar).
- [ ] Get QNAP's MIB (QTS SNMP page has a download) and pick the OIDs:
      disk temperature/status, volume free/total, fan RPM, system/CPU
      temperature, plus IF-MIB `ifHCInOctets`/`ifHCOutOctets`.
- [ ] `edot_gateway`: add an `snmp/qnap` receiver to `otel.yml.j2`
      (`endpoint: udp://<qnap-ip>:161`, `version: v3`,
      `collection_interval: 60s`, `metrics:` with `scalar_oids` /
      `column_oids` and `resource_attributes` for disk/volume index), into
      the existing metrics pipeline. Vars in
      `group_vars/edot_gateway.yml`; the SNMPv3 secrets reach the collector
      as environment variables from `/etc/default/edot-collector`, like
      `EDOT_WRITER_PASSWORD`.
- [ ] Nothing to grant: the gateway writes as `edot_writer`, whose role
      (`roles/edot_gateway/defaults/main.yml`) already covers
      `metrics-*-*`.
- [ ] Optional traps: Logstash `snmptrap` pipeline on `1062/udp`
      (non-root; QNAP lets you set the trap port), output to
      `logs-snmp.trap-default`. No firewall to open, as in Step 1.
- [ ] Kibana: a small dashboard (disk temps, volume usage, interface
      throughput) and a rule for disk temperature/volume fill.

## Order

1. Step 0 decisions.
2. Step 1 syslog listeners, then Step 2 QNAP (quick win, supported).
3. Step 5 CoreDNS metrics (reuses the scrape setup Step 3a needs).
4. Step 3a HA, then Step 4 Deco; Step 3b only if needed.
5. Step 8 SNMP for the QNAP (after Step 2, so syslog and SNMP land
   together).
6. Steps 6–7 when wanted.
