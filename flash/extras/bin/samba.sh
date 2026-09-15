#!/bin/sh

. /mnt/Flash/extras/include
log "Request setup Samba"

# Configuration and derived paths.
SMB_ROOT="${SMB_ROOT:-/Volumes/$SMB_DISK/ShareRoot}"
SMB_HOMES="$SMB_ROOT/Users"
SMB_SHARED="$SMB_ROOT/Shared"
SMB_READ_USERS_HOME="${SMB_READ_USERS_HOME:-0}"
SMB_GUEST="${SMB_GUEST:-1}"

SMB_UID_MIN="${SMB_UID_MIN:-20000}"
SMB_UID_MAX="${SMB_UID_MAX:-20999}"
SMB_GID_MIN="${SMB_GID_MIN:-4450}"
SMB_GROUP_HOME=smb_home
SMB_GROUP_SHARED=smb_shared
SMB_GROUP_SHARED_WRITE=smb_shared_write

SMB_MOUNT="/Volumes/$SMB_DISK"
SMB_CONF="$CONF_DIR/smb.conf"
SMB_SETUP_LOCK_FILE="$RUN_DIR/smb-config.lock"
SMB_LOG_DIR="/var/log"
SMB_LOG_FILE="$SMB_LOG_DIR/log.smbd"
SMB_XATTR_DIR="$HDD_DIR/samba/private"
SMB_PID_DIR="$RUN_DIR"
SMB_LOCK_DIR="/mnt/Locks"
SMB_LOCK_DIR_IN_MEMORY=1
SMB_STATE_DIR="$MEM_DIR/samba/state"
SMB_CACHE_DIR="$MEM_DIR/samba/cache"
SMB_PRIVATE_DIR="$MEM_DIR/samba/private"
SMB_NCALRPC_DIR="$MEM_DIR/samba/ncalrpc"

# Functions.
# Stop the native file servers before our smbd takes over.
stopNativeSMB() {
    local process attempt
    log "Stopping native SMB and AFP"
    for process in wcifsnd wcifsfs afpserver; do
        /usr/bin/pkill "^$process$" 2> /dev/null || :
        attempt=0
        while [ -n "$(ps ax -o ucomm= | sed -n "/^$process$/p")" ]; do
            if [ "$attempt" -eq 5 ]; then
                log "$process still running; sending KILL"
                /usr/bin/pkill -9 "^$process$" 2> /dev/null || :
            elif [ "$attempt" -gt 5 ]; then
                log "ERROR: can't stop $process"
                return 1
            fi
            sleep 1
            attempt=$((attempt + 1))
        done
    done
}

manageGroups() {
    local gid group
    # remove all smb_ groups
    sed '/^smb_/d' /etc/group > "$SMB_PRIVATE_DIR/group.new" &&
        cat "$SMB_PRIVATE_DIR/group.new" > /etc/group || {
        log "ERROR: failed to remove groups"
        return 1
    }
    rm -f "$SMB_PRIVATE_DIR/group.new"

    gid="$SMB_GID_MIN"
    for group in "$SMB_GROUP_HOME" "$SMB_GROUP_SHARED" "$SMB_GROUP_SHARED_WRITE"; do
        printf '%s:*:%s:\n' "$group" "$gid" >> /etc/group || {
            log "ERROR: can't create group $group"
            return 1
        }
        gid=$((gid + 1))
    done
    log "Created smb groups"
}

removeUsers() {
    local name password uid rest
    while IFS=: read -r name password uid rest; do
        if [ "$uid" -ge "$SMB_UID_MIN" ] && [ "$uid" -le "$SMB_UID_MAX" ]; then
            /usr/sbin/userdel "$name" || log "ERROR: can't delete user $name"
        fi
    done < /etc/passwd
    log "Removed smb users"
}

getUserGroups() {
    local groups
    case "$1" in
        0)
            groups="$SMB_GROUP_HOME,$SMB_GROUP_SHARED_WRITE"
            ;;
        1)
            groups="$SMB_GROUP_SHARED"
            if [ "$SMB_READ_USERS_HOME" = 1 ]; then
                groups="$groups,$SMB_GROUP_HOME"
            fi
            ;;
    esac
    echo "$groups"
}

# $1: login, $2: password, $3: comma-separated groups, $4: UID.
createUser() {
    local userName="$1" userPassword="$2" smbGroups="$3" uid="$4"
    if [ -z "$smbGroups" ]; then
        log "Skip user $userName"
        return 0
    fi
    local ntHash
    if [ "$uid" -gt "$SMB_UID_MAX" ]; then
        log "ERROR: Samba UID range exhausted"
        return 1
    fi
    /usr/sbin/useradd -u "$uid" -g nobody -G "$smbGroups" -d /nonexistent -s /sbin/nologin "$userName" || {
        log "ERROR: can't create user $userName"
        return 1
    }
    if [ "$userName" = guest ]; then
        log "Created user $userName (UID $uid, groups $smbGroups)"
        return 0
    fi
    mkdir -p "$SMB_HOMES/$userName" || {
        log "ERROR: can't create directory for $userName"
        return 1
    }
    ntHash=$(printf '%s\n' "$userPassword" | "$BIN_DIR/mdns-advertiser" --print-nt-hash-from-stdin 2> /dev/null) || {
        log "ERROR: can't generate Samba password hash for $userName"
        return 1
    }
    printf '%s:%s:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX:%s:[U          ]:LCT-%08X:\n' \
        "$userName" "$uid" "$ntHash" "$smbLct" >> "$SMB_PRIVATE_DIR/smbpasswd.new" || return 1
    log "Created user $userName (UID $uid, groups $smbGroups)"
}

# Setup checks and storage preparation.
if ! (
    set -C
    : > "$SMB_SETUP_LOCK_FILE"
) 2> /dev/null; then
    log "Samba setup is already running"
    exit 0
fi
trap 'rm -f "$SMB_SETUP_LOCK_FILE"' 0
trap 'exit 1' HUP INT TERM

if [ -f "$SMB_PID_DIR/smbd.pid" ]; then
    smbPid=$(cat "$SMB_PID_DIR/smbd.pid")
    case "$smbPid" in
        "" | *[!0-9]* | 0 | 1)
            log "ERROR: Samba startup aborted: invalid smbd PID"
            exit 1
            ;;
    esac
    log "Stopping Samba (PID $smbPid)"
    kill "$smbPid" 2> /dev/null || :
    for attempt in 1 2 3 4 5; do
        kill -0 "$smbPid" 2> /dev/null || break
        sleep 1
    done
    if kill -0 "$smbPid" 2> /dev/null; then
        log "Samba still running; sending KILL"
        kill -9 "$smbPid" 2> /dev/null || :
    fi
    rm -f "$SMB_PID_DIR/smbd.pid" || {
        log "ERROR: Samba startup aborted: can't remove smbd PID file"
        exit 1
    }
fi

if [ -z "$SMB_DISK" ]; then
    log "Skip setup: SMB_DISK is not set"
    exit 0
fi

case "$SMB_ROOT" in
    /*) ;;
    *)
        log "ERROR: Samba startup aborted: SMB_ROOT must be an absolute path"
        exit 1
        ;;
esac

if [ -z "$BASE_NAME" ] || [ -z "$TC_IP" ]; then
    log "ERROR: Samba startup aborted: BASE_NAME or TC_IP is not set"
    exit 1
fi

waitMount "$SMB_MOUNT"
waitMount "$HDD_MOUNT"

# Runtime directories and persistent extended-attribute database directory.
for dir in "$SMB_HOMES" "$SMB_PID_DIR" "$SMB_LOCK_DIR" "$SMB_STATE_DIR" "$SMB_CACHE_DIR" "$SMB_PRIVATE_DIR" "$SMB_NCALRPC_DIR" "$SMB_XATTR_DIR"; do
    mkdir -p "$dir" || {
        log "ERROR: Samba startup aborted: can't create $dir"
        exit 1
    }
done

# Separate tmpfs for Samba locks (9 MiB, as in the upstream TC setup).
if [ "$SMB_LOCK_DIR_IN_MEMORY" -eq 1 ]; then
    if ! volumeIsMounted "$SMB_LOCK_DIR"; then
        /sbin/mount_tmpfs -s 9m tmpfs "$SMB_LOCK_DIR" || {
            log "ERROR: Samba startup aborted: can't mount tmpfs at $SMB_LOCK_DIR"
            exit 1
        }
    fi
fi

# Copy only missing binaries.
for binary in smbd mdns-advertiser nbns-advertiser; do
    if [ ! -x "$BIN_DIR/$binary" ]; then
        log "Copying $binary from $HDD_DIR/bin"
        cp -f "$HDD_DIR/bin/$binary" "$BIN_DIR/" || log "ERROR: can't copy $binary"
    fi
done

# Groups, Unix users and Samba password database.
# Read ACP once; an empty result imports no users.
usrd=$(/usr/bin/acp -A usrd 2> /dev/null)
manageGroups || {
    log "ERROR: Samba startup aborted: can't prepare groups"
    exit 1
}
removeUsers
uid=$SMB_UID_MIN
(
    umask 077
    : > "$SMB_PRIVATE_DIR/smbpasswd.new" && chmod 600 "$SMB_PRIVATE_DIR/smbpasswd.new"
) || {
    log "ERROR: Samba startup aborted: can't prepare password file"
    exit 1
}
smbLct=$(date +%s)

createUser guest "" "$SMB_GROUP_SHARED" "$uid" || log "ERROR: failed to create guest user"
uid=$((uid + 1))

depth=0
while read -r line; do
    case "$line" in
        "{")
            depth=$((depth + 1))
            if [ "$depth" -eq 2 ]; then
                userName="" userPassword="" userAccess=""
            fi
            ;;
        "}")
            if [ "$depth" -eq 2 ]; then
                createUser "$userName" "$userPassword" "$(getUserGroups "$userAccess")" "$uid" || log "ERROR: failed to create user $userName"
                uid=$((uid + 1))
            fi
            depth=$((depth - 1))
            ;;
        name=* | password=* | fileSharingAccess=*)
            if [ "$depth" -eq 2 ]; then
                value="${line#*=}"
                value="${value#\"}"
                value="${value%\"}"
                case "$line" in
                    name=*) userName="$value" ;;
                    password=*) userPassword="$value" ;;
                    fileSharingAccess=*) userAccess="$value" ;;
                esac
            fi
            ;;
    esac
done << EOF
$usrd
EOF
unset usrd userPassword value line
mv -f "$SMB_PRIVATE_DIR/smbpasswd.new" "$SMB_PRIVATE_DIR/smbpasswd" || {
    log "ERROR: Samba startup aborted: can't install password file"
    exit 1
}

# Generate the configuration with the current runtime values.
log "Generating Samba configuration"
if ! (. "$SH_DIR/smb.conf.sh") > "$SMB_CONF.new" ||
    ! mv -f "$SMB_CONF.new" "$SMB_CONF"; then
    log "ERROR: Samba startup aborted: can't generate configuration"
    exit 1
fi

stopNativeSMB || {
    log "ERROR: Samba startup aborted: can't stop native file servers"
    exit 1
}

log "Starting Samba"
"$BIN_DIR/smbd" -D -l "$SMB_LOG_DIR" -s "$SMB_CONF" --option="log file=$SMB_LOG_FILE" || {
    log "ERROR: Samba startup aborted: smbd failed to start"
    exit 1
}
