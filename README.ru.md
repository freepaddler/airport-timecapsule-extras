[English](README.md) | **Русский**

# Airport Time Capsule Extras

## Описание
Расширяет возможности Apple Time Capsule как домашнего маршрутизатора:

1. Дополнительные опции DHCP-сервера.
2. Локальная DNS-зона с автоматическим добавлением записей для DHCP-клиентов.
3. Перенаправление DNS-запросов на внешние серверы, в том числе на отдельные серверы для конкретных зон.
4. Статические IPsec/ESP-туннели с заданными вручную SPI и ключами, без согласования через IKE.
5. Постоянное монтирование встроенного диска: диск может уходить в idle с остановкой вращения, оставаясь смонтированным.
6. Samba 4 (SMB 2/3) как замена штатных файловых серверов, с NBNS и mDNS для обнаружения в сети.

Управление настройками и пользователями сохраняется через AirPort Utility (если иное не указано в конфигурации). При запуске Samba штатные SMB и AFP останавливаются, а mDNS advertiser заменяет штатный mDNSResponder и публикует SMB, AirPort и Device Info.

Нормально переживает перезагрузки TC

Проект рассчитан только на Time Capsule со встроенным диском `/Volumes/dk2`. Проверялось на Time Capsule 802.11ac с прошивкой 7.9.1.

## Установка

Нужен [root-доступ на TC](https://habr.com/ru/post/501404/).

Файлы размещаются по фиксированным путям; базовый каталог задавать не нужно:

| В репозитории | На Time Capsule | Назначение |
| --- | --- | --- |
| `extras.conf` | `/mnt/Flash/extras.conf` | Пользовательские настройки |
| `flash/rc.local` | `/mnt/Flash/rc.local` | Запуск при загрузке |
| `flash/extras/` | `/mnt/Flash/extras/` | Скрипты и общий `include` |
| `hdd/extras/bin/` | `/Volumes/dk2/extras/bin/` | Бинарники DNS, Samba, NBNS и mDNS |

1. Настроить `extras.conf` и скопировать его в `/mnt/Flash/extras.conf`.
2. Скопировать `flash/rc.local`, `flash/extras/` и `hdd/extras/` по указанным путям. Встроенный диск должен быть смонтирован в `/Volumes/dk2`.
3. Запустить `/mnt/Flash/extras/setup.sh`.

`install.sh` копирует содержимое `flash/` и `hdd/` на SSH-хост `tc`. Файл `extras.conf` нужно скопировать отдельно.

При запуске создаются:

- `/mnt/Flash/extras/conf/` — генерируемые конфиги и DHCP leases;
- `/mnt/Memory/extras/` — копии бинарников, PID-файлы, переменные и временные данные сервисов;
- `/mnt/Locks/` — RAM-диск для блокировок Samba;
- `/Volumes/dk2/extras/samba/private/` — постоянная база расширенных атрибутов Samba.

Общие файлы находятся в `/Volumes/dk2/ShareRoot/Shared`, персональные — в `/Volumes/dk2/ShareRoot/Users/<имя пользователя>`.

## Настройка

1. Изменить настройки в `/mnt/Flash/extras.conf`.
2. Запустить `/mnt/Flash/extras/setup.sh`, чтобы применить изменения.

### DHCP static leases
+ Настраиваются через Airport Uitility
+ Если fixed-address резеревируется на client-dhcp-id, то client-dhcp-id будет использоваться как hostname для этой записи в DNS
+ Если fixed-address резервируется на MAC адрес, то такой хост не будет зарегистрирован в DNS. если нужна его регистрация в DNS - добавить его
client-dhcp-id на тот же ip, что и MAC

### Настройка опций DHCP server
в файле `/mnt/Flash/extras.conf`:
+ DHCPD_GLOBAL - глобальные опции (для всех скоупов)
+ DHCPD_LAN - опции для скоупа локальной сети (НЕ гостевой)

Переменные должны быть multiline - одна опция на строку

применение параметров:

```sh
/mnt/Flash/extras/bin/dhcpd.sh configure
/mnt/Flash/extras/bin/dhcpd.sh restart
```

### Настройка DNS
в файле `/mnt/Flash/extras.conf`:
+ ZONE - имя локальной DNS зоны (имя гостевой зоны будет guest.$ZONE)
+ DNS_STATIC - статические записи в DNS (в формате https://cr.yp.to/djbdns/tinydns-data.html), multiline, одна запись на строку
+ DNS_ACCESS - "внешние" сети, которые имеют право использовать наш DNS север, предназначение - сети на других концах туннелей. Формат записи сеть: `192.168` или `172.16.20`. Указываются в строке через пробел: `DNS_ACCESS="192.168 172.16.20"`
+ DNS_FORWARD - тип работы резолвера
    + root - рекурсивный резолвер с кэшированием, использующий ip адреса root серверов dns. (для получения/обновления адресов root серверов выполнить: `/mnt/Flash/extras/bin/dns.sh update_root`). Если выбран этот режим, а списка root.ip нет, то будет использоваться поведение по-умолчанию (DNS_FORWARD=)
    + список ip адресов dns серверов (forwarder) - перенаправлять все запросы к указанным dns серверам (DNS_FORWARD="1.0.0.1 1.1.1.1")
    + не задано (DNS_FORWARD=) - штатный режим работы Airport TC
+ DNS_EXTERNAL - зоны, которые нужно явно нужно запрашивать у конкретных dns серверов, multiline, одна запись на строку
    + `some.local.zone 192.168.1.1`

применение параметров:
```sh
/mnt/Flash/extras/bin/dns.sh configure
/mnt/Flash/extras/bin/dns.sh setup_dnscache
```

### Настройка SMB и обнаружения в сети

В `/mnt/Flash/extras.conf`:

| Параметр | По умолчанию | Назначение |
| --- | --- | --- |
| `SMB_DISK` | `"dk2"` | Раздел встроенного диска. Пустое значение отключает Samba и её NBNS/mDNS advertiser'ы |
| `SMB_GUEST` | `1` | `1` — разрешить гостю чтение общей шары `Shared`; `0` — запретить гостевой доступ |
| `SMB_READ_USERS_HOME` | `1` | `1` — разрешить read-only пользователям запись в собственную персональную папку; `0` — оставить только чтение общей шары |

Поддерживается только режим доступа через учётные записи пользователей: в AirPort Utility для защиты общих дисков нужно выбрать «С учётными записями» (With accounts). Режимы с паролем устройства (AirPort Password) или отдельным паролем диска (Disk Password) не поддерживаются.

Пользователи, пароли и права файлового доступа задаются через AirPort Utility и считываются при запуске Samba:

- read/write — чтение и запись в общей и собственной персональной папке;
- read-only — чтение общей папки; доступ к собственной папке с записью определяется `SMB_READ_USERS_HOME`;
- no access — пользователь не создаётся в Samba. При включённом гостевом доступе неизвестный пользователь может подключиться как гость и читать общую папку.

Поддержка Time Machine включена только на персональных шарах `[homes]` через `fruit:time machine = yes`: Samba сообщает клиенту о ней по SMB средствами модуля `vfs_fruit`. На общей шаре `Shared` поддержка Time Machine выключена; сам `vfs_fruit` используется и там для совместимости с macOS.

Объявление дисков `_adisk` сознательно отключено: в выбранной схеме мы используем подключение к персональной SMB-шаре и её поддержку Time Machine, без отдельного Bonjour-объявления диска. NBNS отвечает на запросы NetBIOS-имени, mDNS публикует SMB, AirPort и Device Info (`TimeCapsule8,119`). Объявления AFP и принтеров не включены.

Применение параметров:

```sh
/mnt/Flash/extras/bin/samba.sh
```

### Логи

- `/var/log/extras.log` — общий лог; `log-watchd` проверяет размер каждые `LOG_FILE_SIZE_CHECK` секунд и при достижении порога переносит его в `extras.log.old`.
- `/var/log/log.smbd` — лог Samba; Samba сама выполняет ротацию в `log.smbd.old`.
- `LOG_FILE_SIZE=512` задаёт порог в KiB для обоих логов; `LOG_FILE_SIZE_CHECK=14400` — интервал проверки общего лога (4 часа). Между проверками общий лог может превышать порог.
- При `DEBUG=1` дополнительно пишутся `/var/log/nbns.log` и `/var/log/mdns.log`; они не ротируются. При `DEBUG=0` вывод advertiser'ов направляется в `/dev/null`.

### Настройка туннелей
в файле `/mnt/Flash/extras.conf`:
+ tunnels - перечень туннелей через пробел: `tunnels="TUN1 TUN2"`

Для каждого туннеля TUNx:
+ TUNx_PUB - публичный ip адрес удаленной стороны туннеля
+ TUNx_IP - приватный ip адрес удаленной стороны туннеля
+ TUNx_NET - сети, находящиеся на удаленной стороне туннеля в формате `"192.168.1.0/24 192.168.2.0/34"`
+ TUNx_SPI_IN - идентификатор _входящего_ (по отношению к TC) ipsec SPI
+ TUNx_KEY_IN - ключ шифрования ESP _входящего_ SPI
+ TUNx_SPI_OUT - идентификатор _исходящего_ (по отношению к TC) ipsec SPI
+ TUNx_KEY_OUT - ключ шифрования ESP _исходящего_ SPI

применение параметров:
```sh
/mnt/Flash/extras/bin/tunnels.sh
```

Из гостевой сети туннели также будут доступны, поэтому _потребуется_ фильтровать трафик с гостевых сетей _на удаленной стороне туннеля_

#### настройка туннеля на удаленной стороне
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

где:
+ $TC_IP - приватный (LAN) IP адрес Airport TC
+ $TC_PUB - публичный IP адрес Airport TC
+ $TC_NET - Airpot TC LAN network


## TODO

- Проверить работу со статической конфигурацией публичного интерфейса.
- Проверить подключение внешних USB-дисков к Time Capsule и продумать их поддержку. При её добавлении использовать имена партиций как имена шар.
- Добавить поддержку принтеров и их объявления через mDNS.

## Заметки

### ifwatchd
ifwatchd ждет окнчания выполнения запущенного if-up/if-down скрипта перед выполнением следующего, даже если события произошли на разных интерфейсах, поэтому используются дополнительные скрипты if-up-interface.sh

### Туннели
+ использовать только esp transport
+ режим esp tunnel без gif интерфейса - просаживает пропускную способность входящего из туннеля трафика приблизительно в 10(!) раз
+ режим esp tunnel c использованием gif интерфейса не работает, потому что в gif интерфейс попадает не деинкапсулированный входящий трафик из ipsec
+ дополнительное использование ah - просаживает пропускную способность входящего из туннеля трафика приблизительно в 2 раза


### NetBSD cross-compile

Для запуска tinydns на TC нужно было собрать бинарники:
+ **32bit**
+ архитектура **earmv4**
+ со **статически** линкованными библиотеками

**ВАЖНО:** *в `/mnt/Flash` всего 1M места, туда мало что влезет, полученные 2 бинарника не влезли. Пытался собрать архиватор (gzip, bzip2, compress, unzip) - они получаются минимум 600k, а архив с бинарниками tinydns ~ 550k, поэтому бессмысленны (в базе TC архиваторов нет)*

Работало на NetBSD 9.0 и 9.2 x86_64 в UTM(qemu)

В 6.0 нет нужной архитектуры для кросс-компиляции: `-m evbarm -a earmv4`

Запустить arm версии NetBSD не получилось, пробовал: UTM(qemu), Fusion

#### сборка окружения (в qemu 6-9 часов)

```shell
cd /usr/src
./build.sh list-arch # list available architectures
LDSTATIC=-static; export LDSTATIC
./build.sh -U -O ~/evbarm-earmv4 -j6 -m evbarm -a earmv4 tools
./build.sh -U -u -O ~/evbarm-earmv4 -f6 -m evbarm -a earmv4 distribution
```

опционально (для сборки статично линкованными):
* LDSTATIC=-static
* или добавить в /etc/mk.conf

### сборка того, что есть в `usr/src/`

Часть системных утилит можно просто собрать без pkgsrc:

```shell
cd /usr/src/{usr.bin,usr.sbin,external....}
/root/evbarm-earmv4/tooldir.NetBSD-9.0-amd64/bin/nbmake-earmv4 install
```

прочее - из портов

#### ручная установка портов

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

Дальше в /usr/pkgsrc/category/port и пробовать make. Результат в work.earmv4

Для сборки БЕЗ кросс-компиляции: `make USE_CROSS_COMPILE=no`

#### Разное

архитектуру бинарника и какие либы использует (static/dynamic) определяем командой `file`

Если при сборке пакета выполняются только что собранные бинарники, то они не выполнятся из-за разницы архитектур. В этом случае:
1. собрать в текущей архитектуре
2. в Makefile пакета (в distfiles) указать полный путь к только собранным файлам при вызове (добавляем NO_CHECKSUM=yes при вызове make)
3. посмотреть примененные патчи, может какие-то можно выкинуть

Для сборки со статически линкованными библиотеками, если не работает LDSTATIC=-static добавлять строку `-static` при вызове компилятора:
* в Makefile дистрибутива (в distfiles)
* потом в package Makefile
* потом по цепочке *.mk файлов (брать из package Makefile)


### Useful links
+ djbdns:
    + https://cr.yp.to/djbdns.html
    + https://www.fefe.de/djbdns/
    + http://www.lifewithdjbdns.org
+ NetBSD cross-compile
    + https://e17i.github.io/articles-timecapsule-crossbuild/
    + https://ftp.netbsd.org/pub/pkgsrc/current/pkgsrc/doc/HOWTO-use-crosscompile
    + https://ftp.netbsd.org/pub/pkgsrc/stable/pkgsrc/doc/HOWTO-dev-crosscompile
    + https://www.netbsd.org/docs/guide/en/chap-build.html
+ Airport access & management
    + https://github.com/x56/airpyrt-tools
    + https://github.com/samuelthomas2774/airport

### Источник бинарников Samba

В `hdd/extras/bin` находятся бинарники для Time Capsule 5-го поколения (NetBSD 6, ARM little-endian; статическая сборка `earmv4`):

| Бинарник | Путь в исходном репозитории | Источник |
| --- | --- | --- |
| `smbd` | `bin/samba4/smbd` | TimeCapsuleSMB v2.2.9 |
| `mdns-advertiser` | `bin/mdns/mdns-advertiser` | TimeCapsuleSMB v2.2.9 |
| `nbns-advertiser` | `bin/nbns/nbns-advertiser` | TimeCapsuleSMB v2.2.9 |

Бинарники взяты из релиза [TimeCapsuleSMB v2.2.9](https://github.com/jamesyc/TimeCapsuleSMB/releases/tag/v2.2.9). В этом релизе NT-хеши паролей вычисляет `mdns-advertiser`.
