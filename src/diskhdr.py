#!/usr/bin/python3

import json
import sys
import os
import stat
import subprocess
import tempfile
import time

SYNOPSIS="""\
Usage: diskhdr [JSONFILE|help] [COMMAND] [ARG]...
Tool to format disk or file specified by a json file.

Without COMMAND it will just check json file or display this help.

COMMANDS:
  part <FILE|BLOCKDEV>...
  format <FILE|BLOCKDEVICE>...
  mount <SYSTEM_IDX> <FILE|BLOCKDEVICE> <MOUNTPOINT_PATH>
  umount <SYSTEM_IDX> <FILE|BLOCKDEVICE> <MOUNTPOINT_PATH>
  fstab <SYSTEM_IDX> <FILE|BLOCKDEVICE>
  swapsize <DISK_IDX>
  minsize <DISK_IDX>
  mounts <DISK_IDX>
  help
"""

CMD_lIST = ["part", "format", "mount", "mounts", "umount", "fstab", "swapsize", "minsize"]

log_out = print
log_msg = log_out

def log_err(msg):
    log_out("\033[31m" + msg + "\033[0m", file=sys.stderr)

def die(err_code, err_msg):
    log_err(err_msg)
    sys.exit(err_code)

def str_is_help(strin):
    if strin.lower() in ("h", "help", "-h", "-help", "--help"):
        return True
    return False

if len(sys.argv) < 2 or str_is_help(sys.argv[1]):
    log_out(SYNOPSIS)
    sys.exit(0)
else:
    if "--help" in sys.argv or "-help" in sys.argv or "-h" in sys.argv:
        log_out(SYNOPSIS)
        sys.exit(0)
    if len(sys.argv) > 2:
        if str_is_help(sys.argv[2]):
            log_out(SYNOPSIS)
            sys.exit(0)
        elif not sys.argv[2] in CMD_lIST:
            log_out(SYNOPSIS)
            die(1, "Unknown command %s" % sys.argv[2])
            sys.exit(0)

class DiskHandlerException(Exception):
    def __init__(self, message):
        super(DiskHandlerException, self).__init__(message)

def get_mo_size(size_str):
    for suffix in ["T","TB","TO","Tb","To","t","tb","to"]:
        if size_str.endswith(suffix):
            return int(size_str[:-len(suffix)]) * 1024 * 1024

    for suffix in ["G","GB","GO","Gb","Go","g","gb","go"]:
        if size_str.endswith(suffix):
            return int(size_str[:-len(suffix)]) * 1024

    for suffix in ["M","MB","MO","Mb","Mo","m","mb","mo"]:
        if size_str.endswith(suffix):
            return int(size_str[:-len(suffix)])

    raise DiskHandlerException("get_mo_size: No size suffix found")

def dkhr_check_disk_repr(disk_repr):
    if not "table" in disk_repr.keys():
        raise DiskHandlerException("check disk: the key 'table' missing")

    if not "parts" in disk_repr.keys():
        raise DiskHandlerException("check disk: the key 'parts' missing")

    if len(disk_repr["parts"]) == 0:
        raise DiskHandlerException("check disk: No partitions")

    if disk_repr["table"] == "msdos":
        if len(disk_repr["parts"]) > 4:
            raise DiskHandlerException("check disk: handle a maximum of 4 in msdos table (count:%d)"
                                       % len(disk_repr["parts"]))
        for part in disk_repr["parts"]:
            if not "type" in part.keys():
                DiskHandlerException("check part: the key 'type' missing")
    elif disk_repr["table"] == "gpt":
        if len(disk_repr["parts"]) > 128:
            raise DiskHandlerException("check disk: Maximum partitions in gpt table is 128 (count:%d)"
                                % len(disk_repr["parts"]))
    else:
        raise DiskHandlerException("check disk: Unhandled partition table %s" % disk_repr["table"])

    for part in disk_repr["parts"]:
        if not "type" in part.keys():
            DiskHandlerException("check part: the key 'type' missing")
        if "flags" in part.keys():
            for flag in part["flags"]:
                if not flag in ["boot", "root", "swap", "hidden", "raid", "lvm",
                                "lba", "hp-service", "palo", "prep", "msftres",
                                "bios_grub", "atvrecv", "diag", "legacy_boot",
                                "msftdata", "irst", "esp", "chromeos_kernel",
                                "bls_boot"]:
                    raise DiskHandlerException("Unexpected flag %s" % flag)

def check_disks_repr_list(disks_list):
    if len(disks_list) == 0:
        raise DiskHandlerException("check disks: No disk found")

    if len(disks_list) != 1:
        raise DiskHandlerException("check disks: Only one disk is currently available")

    dkhr_check_disk_repr(disks_list[0])

def check_systems_repr_list(systems_list, disks_list):
    check_disks_repr_list(disks_list)

    if len(systems_list) == 0:
        raise DiskHandlerException("check systems: No system found")

    if len(systems_list) != 1:
        raise DiskHandlerException("check systems: Only one system is currently available")

try:
    diskhdr_obj = json.loads(open(sys.argv[1], "r").read())
except json.decoder.JSONDecodeError as e:
    die(1, "Unable to decode json\n" + str(e))
except Exception as e:
    die(1,
        "problem with path {path}\n{errmsg}".format(path=sys.argv[1],
                                                    errmsg=str(e)))

if not "disks" in diskhdr_obj.keys():
    die(1, "the key 'disks' missing")

if not "systems" in diskhdr_obj.keys():
    die(1, "the key 'systems' missing")

try:
    check_systems_repr_list(diskhdr_obj["systems"], diskhdr_obj["disks"])
except DiskHandlerException as e:
    die(1, "Check error\n%s" % e)

if len(sys.argv) < 3:
    sys.exit(0)

if os.geteuid() != 0:
    die(1, "Commands need root privilegies")

DST_BLOCK = 0
DST_FILE = 1

def check_dstpath(dstpath):
    if not os.path.exists(dstpath):
        raise DiskHandlerException("check_dstpath: %s does not exist" % dstpath)

    mode = os.stat(dstpath).st_mode
    if stat.S_ISREG(mode):
        return DST_FILE
    elif stat.S_ISBLK(mode):
        return DST_BLOCK
    else:
        raise DiskHandlerException("check_dstpath: Unhandled type of file (%s)" % dstpath)

def get_destination_mo_size(path_dst):
    if check_dstpath(path_dst) == DST_FILE:
        return int(subprocess.check_output("stat -c %s " + path_dst,
                                           shell=True).replace(b"\n", b"")) / 1048576
    else:
        return int(subprocess.check_output("parted -s -m " + path_dst + " -- unit B print 2> /dev/null | grep " + path_dst + " | cut -d: -f 2",
                                           shell=True).replace(b"\n", b"").replace(b"B", b"")) / 1048576

def _gen_parted_create_msdos_cmd(part, start_addr, end_addr):
    """Factorisation of gen_parted_create_cmd"""
    return "mkpart primary {type} {start} {end}".format(type=part["type"],
                                                        start=start_addr,
                                                        end=end_addr)

def _gen_parted_create_gpt_cmd(part, start_addr, end_addr):
    """Factorisation of gen_parted_create_cmd"""
    if "partname" in part.keys():
        return "mkpart {partname} {type} {start} {end}".format(partname=part["partname"],
                                                               type=part["type"],
                                                               start=start_addr,
                                                               end=end_addr)
    else:
        return "mkpart {type} {start} {end}".format(type=part["type"],
                                                    start=start_addr,
                                                    end=end_addr)

def gen_parted_create_cmd(disk_repr, path_dst):
    # Fill missing size
    size_missing = False
    part_missing_size = None
    for part in disk_repr["parts"]:
        if not "size" in part.keys():
            if size_missing == True:
                raise DiskHandlerException("gen_parted_create_cmd: Missing partition size in more than one partition")
            size_missing = True
            part_missing_size = part
    if size_missing:
        disk_size = get_destination_mo_size(path_dst)
        enabled_size = 0
        for part in disk_repr["parts"]:
            if  part != part_missing_size:
                enabled_size += get_mo_size(part["size"])
        if disk_size < enabled_size:
            raise DiskHandlerException("gen_parted_create_cmd: Disk size is to small to contain partitions (size > %dMO)" % enabled_size)
        part_missing_size["size"] = "%dM" % (disk_size - enabled_size)

    # Generate partition command
    parted_cmd = "parted -s " + path_dst + " -- mktable " + disk_repr["table"]
    if disk_repr["table"] == "msdos":
        _gen_parted_cb = _gen_parted_create_msdos_cmd
    else:# if disk_repr["table"] == "gpt":
        _gen_parted_cb = _gen_parted_create_gpt_cmd
    last_offset = 0
    last_partition = False
    part_num = 1
    for part in disk_repr["parts"]:
        if part == disk_repr["parts"][-1]:
            last_partition = True
        end_offset = last_offset + get_mo_size(part["size"])
        parted_cmd += " %s" % _gen_parted_cb(part,
                                             "0%" if last_offset == 0 else "%dMB" % last_offset,
                                             "%dMB" % end_offset if not last_partition else "100%")
        if "flags" in  part.keys():
            for flag in part["flags"]:
                parted_cmd += " set {part_num_arg} {flag_arg} on".format(part_num_arg=part_num,
                                                                         flag_arg=flag)
        last_offset = end_offset
        part_num += 1
    return parted_cmd

def wait_path(path):
    # Get a better solution than sleep to wait partition (part probe check etc)
    count=20
    while count > 0:
        if os.path.exists(path):
            return
        count -= 1
        time.sleep(.5)
    raise DiskHandlerException("wait_path: timeout on %s" % path)

def gen_mkfs_cmd(part_list, blk_prefix):
    mkfs_cmd_list = []
    part_num = 1
    for part in part_list:
        part_path = blk_prefix + "%d" % part_num
        wait_path(part_path)
        new_mkfs_cmd = None
        if part["type"] == "fat32":
            new_mkfs_cmd = "mkfs.fat -F32"
            if "fsname" in part.keys():
                new_mkfs_cmd += " -n %s" % part["fsname"]
        elif part["type"] == "ext4":
            new_mkfs_cmd = "mkfs.ext4 -F"
            if "fsname" in part.keys():
                new_mkfs_cmd += " -L %s" % part["fsname"]
        elif part["type"] == "linux-swap":
            new_mkfs_cmd = "mkswap -f"
            if "fsname" in part.keys():
                new_mkfs_cmd += " -L %s" % part["fsname"]
        elif part["type"] == "ntfs":
            new_mkfs_cmd = "mkfs.ntfs -f"
            if "fsname" in part.keys():
                new_mkfs_cmd += " -L %s" % part["fsname"]
        else:
            raise DiskHandlerException("Unhandled partition type %s" % part["type"])
        new_mkfs_cmd += " %s > /dev/null 2>&1" % part_path
        mkfs_cmd_list.append(new_mkfs_cmd)
        part_num += 1
    return " && ".join(mkfs_cmd_list)

def kpartx_file(filepath):
    try:
        kpartx_stdout = subprocess.check_output("kpartx -av %s" % filepath,
                                                shell=True)
        kpartx_stdout_list = kpartx_stdout.decode("ascii").split(" ")
        if kpartx_stdout_list[0] != "add" or kpartx_stdout_list[1] != "map":
            raise DiskHandlerException("kpartx_file: kpartx output unexpected")
        loop_num = int(kpartx_stdout_list[2].split("p")[1])
        # log_msg("file {file} mapped via kpartx on /dev/loop{num} (and /dev/mapper/loop{num}p*)".format(file=filepath, num=loop_num))
        return loop_num
    except:
        raise DiskHandlerException("kpartx_file: Unhandled error")

def set_kpartx_if_needed(dst_path):
    "Return loop device number if destination is a file else return None"
    if check_dstpath(dst_path) == DST_FILE:
        return kpartx_file(cmd_n_args[2])
    return None

cmd_n_args = sys.argv[2:]
system_repr_list = diskhdr_obj["systems"]
disks_list = diskhdr_obj["disks"]

def create_mountpoints(system_repr, disks_list, blk_prefix_list):
    if len(disks_list) != len(blk_prefix_list):
        raise DiskHandlerException("create_mountpoints: disk list and block list number mismatch")
    if "parts" in system_repr.keys():
        root_mountpoint = tempfile.mkdtemp(suffix="_diskhdr_mountpoints_gen")
        blkpath = blk_prefix_list[system_repr["disk"]] + "%d" % (system_repr["partidx"] + 1)
        os.system("mount {blk} {mount}".format(blk=blkpath,
                                               mount=root_mountpoint))
        for part in system_repr["parts"]:
            if "mount" in part.keys():
                mountpoint = root_mountpoint + part["mount"]
                os.makedirs(mountpoint)

        os.system("umount %s" % root_mountpoint)
        os.system("rmdir %s" % root_mountpoint)

def mount_system(system_repr, blk_prefix_list, mountpoint):
    blkpath = blk_prefix_list[system_repr["disk"]] + "%d" % (system_repr["partidx"] + 1)
    os.system("mount {blk} {mount}".format(blk=blkpath,
                                           mount=mountpoint))

    if "parts" in system_repr.keys():
        for part in system_repr["parts"]:
            if "mount" in part.keys():
                blkpath = blk_prefix_list[part["disk"]] + "%d" % (part["partidx"] + 1)
                os.system("mount {blk} {mount}".format(blk=blkpath,
                                                       mount=mountpoint + part["mount"]))

def umount_system(system_repr, mountpoint):
    if "parts" in system_repr.keys():
        for part in system_repr["parts"]:
            if "mount" in part.keys():
                os.system("umount %s" % mountpoint + part["mount"])
    os.system("umount %s" % mountpoint)

def get_fsuuid(blk_prefix_list, disk_idx, part_idx):
    blk_path = os.path.realpath(blk_prefix_list[disk_idx] + "%d" % (part_idx + 1))
    lsblk_ret = subprocess.check_output("lsblk -n -o UUID %s" % blk_path,
                                        shell=True)
    return lsblk_ret.decode("ascii")[:-1]

def dump_fstab(system_repr, disks_list, blk_prefix_list):
    if system_repr["type"] != "fstab":
        raise DiskHandlerException("System is not an fstab type")

    fstab_str_list = ["proc /proc proc defaults 0 0"]
    uuid_str = get_fsuuid(blk_prefix_list, system_repr["disk"], system_repr["partidx"])
    fstype_str = disks_list[system_repr["disk"]]["parts"][system_repr["partidx"]]["type"]
    fstab_str_list.append("UUID={uuid} / {fstype} errors=remount-ro 0 1".format(uuid=uuid_str,
                                                                                fstype=fstype_str))
    if "parts" in system_repr.keys():
        for part in system_repr["parts"]:
            disk = disks_list[part["disk"]]
            if "mount" in part.keys():
                uuid_str = get_fsuuid(blk_prefix_list, part["disk"], part["partidx"])
                fstype_str = disk["parts"][part["partidx"]]["type"]
                if fstype_str == "fat32":
                    fstype_str = "vfat"
                fstab_str_list.append("UUID={uuid} {mount} {fstype} rw,users,sync 0 2".format(uuid=uuid_str,
                                                                                              mount=part["mount"],
                                                                                              fstype=fstype_str))
            elif disk["parts"][part["partidx"]]["type"] == "linux-swap":
                uuid_str = get_fsuuid(blk_prefix_list, part["disk"], part["partidx"])
                fstab_str_list.append("UUID=%s none swap sw 0 0" % uuid_str)
    log_out("\n".join(fstab_str_list))

command = cmd_n_args[0]
if command == "part":
    if len(cmd_n_args) < 2:
        log_out(SYNOPSIS)
        die(1, "Wrong number of arguments (multiple device not yet supported)")
    dst_path = os.path.realpath(cmd_n_args[1])
    part_cmd = gen_parted_create_cmd(disks_list[0], dst_path)
    log_msg(part_cmd)
    if os.system(part_cmd) != 0:
        die(1, "Format fail")
elif command == "format":
    if len(cmd_n_args) < 2:
        log_out(SYNOPSIS)
        die(1, "Wrong number of arguments (multiple device not yet supported)")
    dst_path = os.path.realpath(cmd_n_args[1])
    part_cmd = gen_parted_create_cmd(disks_list[0], dst_path)
    part_cmd += " && partprobe %s" % dst_path
    log_msg(part_cmd)
    if os.system(part_cmd) != 0:
        die(1, "Format fail")
    if check_dstpath(dst_path) == DST_FILE:
        loop_num = kpartx_file(dst_path)
        try:
            blk_prefix = "/dev/mapper/loop%dp" % loop_num
            mkfs_cmd = gen_mkfs_cmd(disks_list[0]["parts"], blk_prefix)
            log_msg(mkfs_cmd)
            if os.system(mkfs_cmd) != 0:
                os.system("kpartx -dv %s" % dst_path)
                die(1, "%s: mkfs fail" % command)
            create_mountpoints(system_repr_list[0], disks_list, [blk_prefix])
        except DiskHandlerException as e:
            log_err("Unable to create filesystem\n%s" % e)
        finally:
            os.system("kpartx -dv %s" % dst_path)
    else:
        mkfs_cmd = gen_mkfs_cmd(disks_list[0]["parts"], dst_path)
        log_msg(mkfs_cmd)
        if os.system(mkfs_cmd) != 0:
            die(1, "Filesystems creation fail")
        create_mountpoints(system_repr_list[0], disks_list, [dst_path])
else:
    if command == "swapsize":
        if len(cmd_n_args) != 2:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        disk_idx = int(cmd_n_args[1])
        for part in disks_list[disk_idx]["parts"]:
            if part["type"] == "linux-swap":
                log_out("%d" % get_mo_size(part["size"]))
                sys.exit(0)
    elif command == "minsize":
        if len(cmd_n_args) != 2:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        disk_idx = int(cmd_n_args[1])
        minsize = 0
        for part in disks_list[disk_idx]["parts"]:
            if "size" in part.keys():
                minsize += get_mo_size(part["size"])
        log_out("%d" % minsize)
        sys.exit(0)
    elif command == "mounts":
        if len(cmd_n_args) != 2:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        system_idx = int(cmd_n_args[1])
        mounts = []
        for part in system_repr_list[system_idx]["parts"]:
            if "mount" in part.keys():
                mounts.append(part["mount"])
        log_out(" ".join(mounts))
        sys.exit(0)
    elif len(cmd_n_args) < 3:
        log_out(SYNOPSIS)
        die(1, "%s need more arguments" % command)

    system_num = int(cmd_n_args[1])

    dst_path = os.path.realpath(cmd_n_args[2])

    if command == "mount":
        if len(cmd_n_args) != 4:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        mount_point = cmd_n_args[3]
        loop_num = set_kpartx_if_needed(dst_path)
        if loop_num != None:
            mount_system(system_repr_list[system_num], ["/dev/mapper/loop%dp" % loop_num], mount_point)
            print("/dev/loop%d" % loop_num)
        else:
            mount_system(system_repr_list[system_num], [dst_path], mount_point)
            print(dst_path)
    elif command == "umount":
        if len(cmd_n_args) != 4:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        mount_point = cmd_n_args[3]
        umount_system(system_repr_list[system_num], mount_point)
        if check_dstpath(dst_path) == DST_FILE:
            os.system("kpartx -dv %s" % dst_path)
    elif command == "fstab":
        if len(cmd_n_args) != 3:
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        loop_num = set_kpartx_if_needed(dst_path)
        if loop_num != None:
            blk_prefix = "/dev/mapper/loop%dp" % loop_num
            dump_fstab(system_repr_list[system_num], disks_list, ["/dev/mapper/loop%dp" % loop_num])
            os.system("kpartx -d %s > /dev/null 2>&1" % dst_path)
        else:
            dump_fstab(system_repr_list[system_num], disks_list, [dst_path])
    else:
        die(1, "Unknown command %s" % command)
