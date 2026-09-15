#!/bin/sh
# Sourced by samba.sh; write the generated configuration to stdout.
smbGuestOk=no
[ "$SMB_GUEST" = 1 ] && smbGuestOk=yes

cat << EOF
[global]
# identity
    netbios name = $BASE_NAME
    interfaces = $TC_IP/24
    server string = $BASE_NAME Samba 4
    fruit:model = TimeCapsule8,119

# authentication and guest access
    security = user
    map to guest = Bad User
    restrict anonymous = 0
    guest account = guest
    guest ok = no
    null passwords = no

# authentication files
    passdb backend = smbpasswd:$SMB_PRIVATE_DIR/smbpasswd

# directories and helpers
    dfree command = $SH_DIR/dfree.sh
    pid directory = $SMB_PID_DIR
    lock directory = $SMB_LOCK_DIR
    state directory = $SMB_STATE_DIR
    cache directory = $SMB_CACHE_DIR
    private dir = $SMB_PRIVATE_DIR
    ncalrpc dir = $SMB_NCALRPC_DIR

# logging
    log file = $SMB_LOG_FILE
    # KiB per log file
    max log size = $LOG_FILE_SIZE
    # 1: normal logging; 3: temporary diagnostics
    log level = 1

# protocol (SMB 2 through 3.1.1; SMB 1 disabled)
    server min protocol = SMB2_02
    server max protocol = SMB3_11
    server multi channel support = no
    smb ports = 445

# network defaults
    workgroup = WORKGROUP
    bind interfaces only = yes

# printers
    load printers = no
    disable spoolss = yes

# runtime defaults
    dbwrap_tdb_max_dead:* = 0
    aio read size = 0
    aio write size = 0
    deadtime = 15
    max open files = 512
    max smbd processes = 8
    reset on zero vc = yes

# Apple compatibility defaults
    dos charset = ASCII
    ea support = yes
    fruit:aapl = yes
    fruit:advertise_fullsync = true
    fruit:nfs_aces = no
    fruit:veto_appledouble = yes
    fruit:wipe_intentionally_left_blank_rfork = yes
    fruit:delete_empty_adfiles = yes

[Shared]
    comment = Shared folder
    path = $SMB_SHARED
    browseable = yes
    read only = yes
    guest ok = $smbGuestOk
    valid users = @smb_shared @smb_shared_write
    write list = @smb_shared_write

# Apple metadata and extended attributes
    vfs objects = catia fruit streams_xattr acl_xattr xattr_tdb
    acl_xattr:ignore system acls = yes
    streams_xattr:max xattrs per stream = 2
    fruit:resource = file
    fruit:metadata = stream
    fruit:encoding = native
    fruit:time machine = no
    fruit:posix_rename = yes
    xattr_tdb:file = $SMB_XATTR_DIR/xattr.tdb

# filesystem ownership and permissions
    force user = root
    force group = wheel
    create mask = 0666
    directory mask = 0777
    force create mode = 0666
    force directory mode = 0777

[homes]
    comment = Personal folder
    browseable = no
    read only = no
    guest ok = no
    valid users = @smb_home
    # Always open the authenticated user's folder, regardless of the share name.
    path = $SMB_HOMES/%U
    vfs objects = catia fruit streams_xattr acl_xattr xattr_tdb
    acl_xattr:ignore system acls = yes
    streams_xattr:max xattrs per stream = 2
    fruit:resource = file
    fruit:metadata = stream
    fruit:encoding = native
    fruit:time machine = yes
    fruit:posix_rename = yes
    xattr_tdb:file = $SMB_XATTR_DIR/xattr.tdb
    force user = root
    force group = wheel
    create mask = 0666
    directory mask = 0777
    force create mode = 0666
    force directory mode = 0777
EOF
