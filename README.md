**English** | [Русский](README.ru.md)

# Airport Time Capsule Extras

## Overview

Adds features to an Apple Time Capsule used as a home router:

1. Extra DHCP server options.
2. A local DNS zone with automatic records for DHCP clients.
3. DNS forwarding to upstream servers, including separate forwarders for specific zones.
4. Static IPsec/ESP tunnels with manually configured SPI values and keys, without IKE negotiation.
5. Persistent disk mounts: the internal disk stays mounted while still being able to spin down when idle.
6. Samba 4 (SMB 2/3) as a replacement for the built-in file servers, with NBNS and mDNS for network discovery.

Settings and user accounts are still managed through AirPort Utility, unless overridden in the configuration. When Samba starts, it stops the built-in SMB and AFP servers. The mDNS advertiser replaces Apple's mDNSResponder and publishes SMB, AirPort and Device Info.

The setup survives Time Capsule reboots.

This project is for Time Capsule devices with an internal disk at `/Volumes/dk2`. Tested on a Time Capsule 802.11ac running firmware 7.9.1.

## Installation

You need [root access to the Time Capsule](https://habr.com/ru/post/501404/) (guide in Russian).

Files use fixed paths. There is no base directory setting:

| In this repository | On the Time Capsule | Purpose |
| --- | --- | --- |
| `extras.conf` | `/mnt/Flash/extras.conf` | User settings |
| `flash/rc.local` | `/mnt/Flash/rc.local` | Startup entry point |
| `flash/extras/` | `/mnt/Flash/extras/` | Scripts and shared `include` file |
| `hdd/extras/bin/` | `/Volumes/dk2/extras/bin/` | DNS, Samba, NBNS and mDNS binaries |

1. Edit `extras.conf` and copy it to `/mnt/Flash/extras.conf`.
2. Copy `flash/rc.local`, `flash/extras/` and `hdd/extras/` to the paths above. The internal disk must be mounted at `/Volumes/dk2`.
3. Run `/mnt/Flash/extras/setup.sh`.

`install.sh` copies the contents of `flash/` and `hdd/` to the SSH host `tc`. Copy `extras.conf` separately.

The scripts create these directories at startup:

- `/mnt/Flash/extras/conf/` — generated configuration files and DHCP leases.
- `/mnt/Memory/extras/` — runtime copies of binaries, PID files, shared variables and temporary service data.
- `/mnt/Locks/` — a RAM disk for Samba locks.
- `/Volumes/dk2/extras/samba/private/` — Samba's persistent extended attribute database.

Shared files live in `/Volumes/dk2/ShareRoot/Shared`. Personal folders live in `/Volumes/dk2/ShareRoot/Users/<username>`.

## Configuration

1. Edit the settings in `/mnt/Flash/extras.conf`.
2. Run `/mnt/Flash/extras/setup.sh` to apply the changes.

### Static DHCP leases

- Configure reservations in AirPort Utility.
- For a reservation using `client-dhcp-id`, that ID becomes the hostname in local DNS.
- A reservation using only a MAC address does not create a DNS record. To add one, create a `client-dhcp-id` reservation for the same IP address.

### DHCP server options

In `/mnt/Flash/extras.conf`:

- `DHCPD_GLOBAL` — options for all scopes.
- `DHCPD_LAN` — options for the main LAN scope, not the guest network.

Use multiline values, with one option per line.

Apply the settings:

```sh
/mnt/Flash/extras/bin/dhcpd.sh configure
/mnt/Flash/extras/bin/dhcpd.sh restart
```

### DNS

In `/mnt/Flash/extras.conf`:

- `ZONE` — the local DNS zone. The guest zone is `guest.$ZONE`.
- `DNS_STATIC` — static records in [tinydns format](https://cr.yp.to/djbdns/tinydns-data.html), one per line.
- `DNS_ACCESS` — remote networks allowed to use this DNS server, typically networks at the other end of a tunnel. Use space-separated network prefixes, for example `DNS_ACCESS="192.168 172.16.20"`.
- `DNS_FORWARD` — resolver mode, described below.
- `DNS_EXTERNAL` — zones that should use a specific DNS server, one per line. Example: `some.local.zone 192.168.1.1`.

`DNS_FORWARD` supports three modes:

| Value | Behavior |
| --- | --- |
| `root` | Recursive caching resolver using DNS root servers. Run `/mnt/Flash/extras/bin/dns.sh update_root` to get or update their addresses. If `root.ip` is missing, the default mode is used. |
| `"1.0.0.1 1.1.1.1"` | Forward requests to the listed DNS servers. |
| Empty | Use the Time Capsule's normal DNS behavior. |

Apply the settings:

```sh
/mnt/Flash/extras/bin/dns.sh configure
/mnt/Flash/extras/bin/dns.sh setup_dnscache
```

### SMB and network discovery

In `/mnt/Flash/extras.conf`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `SMB_DISK` | `"dk2"` | Internal disk partition. An empty value disables Samba and its NBNS/mDNS advertisers. |
| `SMB_GUEST` | `1` | `1` allows guests to read the `Shared` share; `0` disables guest access. |
| `SMB_READ_USERS_HOME` | `1` | `1` gives read-only users read/write access to their personal folder; `0` limits them to reading the common share. |

Only account-based disk access is supported. In AirPort Utility, select **With accounts** for shared disk security. **AirPort Password** and **Disk Password** modes are not supported.

Manage usernames, passwords and file access permissions in AirPort Utility. Samba imports them when it starts:

- **Read/write:** read and write access to the common share and the user's personal folder.
- **Read-only:** read access to the common share. `SMB_READ_USERS_HOME` controls whether the user also gets a writable personal folder.
- **No access:** the user is not created in Samba. If guest access is enabled, an unknown user can still connect as a guest and read the common share.

Time Machine support is enabled only on personal shares (`[homes]`) through `fruit:time machine = yes`. Samba reports this capability over SMB using `vfs_fruit`. Time Machine is disabled on `Shared`, although that share also uses `vfs_fruit` for macOS compatibility.

We deliberately leave `_adisk` advertisements disabled. This setup uses a connection to the personal SMB share and its Time Machine support, without a separate Bonjour disk announcement. NBNS answers NetBIOS name queries. mDNS publishes SMB, AirPort and Device Info (`TimeCapsule8,119`). AFP and printer advertisements are disabled.

Apply the settings:

```sh
/mnt/Flash/extras/bin/samba.sh
```

### Logs

- `/var/log/extras.log` — the main log. `log-watchd` checks its size every `LOG_FILE_SIZE_CHECK` seconds and moves it to `extras.log.old` when it reaches the threshold.
- `/var/log/log.smbd` — Samba's log. Samba handles rotation to `log.smbd.old` itself.
- `LOG_FILE_SIZE=512` sets the size threshold in KiB for both logs. `LOG_FILE_SIZE_CHECK=14400` checks the main log every four hours. The main log can grow beyond the threshold between checks.
- `DEBUG=1` also writes `/var/log/nbns.log` and `/var/log/mdns.log`. These debug logs are not rotated. With `DEBUG=0`, advertiser output goes to `/dev/null`.

### Tunnels

In `/mnt/Flash/extras.conf`, list tunnel names separated by spaces: `tunnels="TUN1 TUN2"`.

For each tunnel `TUNx`, set:

- `TUNx_PUB` — the remote endpoint's public IP address.
- `TUNx_IP` — the remote endpoint's private tunnel IP address.
- `TUNx_NET` — remote networks, for example `"192.168.1.0/24 192.168.2.0/24"`.
- `TUNx_SPI_IN` — incoming IPsec SPI, from the Time Capsule's perspective.
- `TUNx_KEY_IN` — encryption key for the incoming ESP SPI.
- `TUNx_SPI_OUT` — outgoing IPsec SPI.
- `TUNx_KEY_OUT` — encryption key for the outgoing ESP SPI.

Apply the settings:

```sh
/mnt/Flash/extras/bin/tunnels.sh
```

Tunnels are also reachable from the guest network. Filter guest traffic at the remote end of the tunnel.

#### Remote endpoint setup

```sh
ifconfig gifX create
ifconfig gifX $TUNx_IP $TC_IP netmask 255.255.255.0
ifconfig gifX tunnel $TUNx_PUB $TC_PUB
setkey -c << EOF
add $TUNx_PUB $TC_PUB esp $TUNx_SPI_IN' -E rijndael-cbc $TUNx_KEY_IN;
add $TC_PUB $TUNx_PUB esp $TUNx_SPI_OUT' -E rijndael-cbc $TUNx_KEY_OUT;
spdadd $TUNx_PUB/32 $TC_PUB/32 ip4 -P out ipsec esp/transport/$TUNx_PUB-$TC_PUB/require;
EOF
route add $TC_NET $TC_IP
```

Here:

- `$TC_IP` — the Time Capsule's private LAN IP address.
- `$TC_PUB` — the Time Capsule's public IP address.
- `$TC_NET` — the Time Capsule's LAN subnet.

## TODO

- Test a static IP configuration on the public interface.
- Test external USB disks connected to the Time Capsule and work out how to support them. Use partition names as share names when adding this support.
- Add printer support and mDNS printer advertisements.

## Notes

### ifwatchd

`ifwatchd` waits for each if-up/if-down script to finish before handling the next event, even for different interfaces. Extra `if-up-interface.sh` scripts are used to avoid blocking other events.

### Tunnels

- Use ESP transport mode.
- In testing, ESP tunnel mode without a `gif` interface reduced incoming throughput by roughly 10 times.
- ESP tunnel mode with a `gif` interface did not work: the interface received traffic before IPsec decapsulation.
- Adding AH reduced incoming throughput by roughly half.

### NetBSD cross-compilation

To run tinydns on the Time Capsule, the binaries were built with:

- **32-bit** code.
- **earmv4** architecture.
- **Statically linked** libraries.

**Flash space is limited:** `/mnt/Flash` has only about 1 MB, and the two binaries did not fit. Building an archive tool did not help: gzip, bzip2, compress and unzip binaries were at least 600 KB, while the compressed tinydns binaries were about 550 KB. The stock firmware has no archive tools.

The build worked on NetBSD 9.0 and 9.2 x86_64 in UTM (QEMU). In the original build experiments, NetBSD 6.0 did not provide the required `-m evbarm -a earmv4` target. Attempts to boot an ARM version of NetBSD in UTM (QEMU) or Fusion were unsuccessful.

#### Building the toolchain and system libraries

This took 6–9 hours in QEMU.

```shell
cd /usr/src
./build.sh list-arch # list available architectures
LDSTATIC=-static; export LDSTATIC
./build.sh -U -O ~/evbarm-earmv4 -j6 -m evbarm -a earmv4 tools
./build.sh -U -u -O ~/evbarm-earmv4 -f6 -m evbarm -a earmv4 distribution
```

For static linking, set `LDSTATIC=-static` in the environment or add it to `/etc/mk.conf`.

### Building tools from `/usr/src/`

Some system utilities can be built without pkgsrc:

```shell
cd /usr/src/{usr.bin,usr.sbin,external....}
/root/evbarm-earmv4/tooldir.NetBSD-9.0-amd64/bin/nbmake-earmv4 install
```

Use pkgsrc for other packages.

#### Installing pkgsrc manually

```shell
rm -rf /usr/pkgsrc
ftp ftp://ftp.NetBSD.org/pub/pkgsrc/stable/pkgsrc.tar.gz
tar -xzf pkgsrc.tar.gz -C /usr
```

#### mk.conf

```shell
LDSTATIC=-static
PKG_DBDIR=/var/db/pkg
USE_CROSS_COMPILE?=yes
CROSSBASE=${LOCALBASE}/cross-${TARGET_ARCH:U${MACHINE_ARCH}}

.if !empty(USE_CROSS_COMPILE:M[yY][eE][sS])
MACHINE=evbarm
MACHINE_ARCH=earmv4
TOOLDIR=/root/evbarm-earmv4/tooldir.NetBSD-9.0-amd64
CROSS_DESTDIR=/root/evbarm-earmv4/destdir.evbarm
PACKAGES=${PKGSRCDIR}/packages.${MACHINE_ARCH}
WRKDIR_BASENAME=work.${MACHINE_ARCH}
USE_CWRAPPERS=no
.endif

CONFIGURE_ENV+= CC_FOR_BUILD=${NATIVE_CC:Q}
CONFIGURE_ENV+= ac_cv_file__dev_urandom=yes
```

Run `make` in `/usr/pkgsrc/category/port`. Build output goes into `work.earmv4`.

To build for the host instead, use `make USE_CROSS_COMPILE=no`.

#### Troubleshooting

Use `file` to check a binary's architecture and whether it is statically or dynamically linked.

Some packages run newly built tools during their build. ARM tools cannot run directly on an x86_64 build host. In that case:

1. Build the tools for the host architecture first.
2. In the package's source Makefile, use the full paths to those host tools. If modifying distfiles, pass `NO_CHECKSUM=yes` to `make`.
3. Review the applied patches to see whether any are unnecessary.

If `LDSTATIC=-static` has no effect, try adding `-static` to the compiler command. Check the upstream Makefile, the pkgsrc package Makefile and the `.mk` files it includes.

### Useful links

**djbdns**

- https://cr.yp.to/djbdns.html
- https://www.fefe.de/djbdns/
- http://www.lifewithdjbdns.org

**NetBSD cross-compilation**

- https://e17i.github.io/articles-timecapsule-crossbuild/
- https://ftp.netbsd.org/pub/pkgsrc/current/pkgsrc/doc/HOWTO-use-crosscompile
- https://ftp.netbsd.org/pub/pkgsrc/stable/pkgsrc/doc/HOWTO-dev-crosscompile
- https://www.netbsd.org/docs/guide/en/chap-build.html

**AirPort access and management**

- https://github.com/x56/airpyrt-tools
- https://github.com/samuelthomas2774/airport

### Samba binary source

`hdd/extras/bin` includes binaries for the 5th-generation Time Capsule (NetBSD 6, little-endian ARM; static `earmv4` builds):

| Binary | Upstream repository path | Source |
| --- | --- | --- |
| `smbd` | `bin/samba4/smbd` | TimeCapsuleSMB v2.2.9 |
| `mdns-advertiser` | `bin/mdns/mdns-advertiser` | TimeCapsuleSMB v2.2.9 |
| `nbns-advertiser` | `bin/nbns/nbns-advertiser` | TimeCapsuleSMB v2.2.9 |

The binaries come from [TimeCapsuleSMB v2.2.9](https://github.com/jamesyc/TimeCapsuleSMB/releases/tag/v2.2.9). In this release, `mdns-advertiser` also generates NT password hashes.
