#!/usr/bin/python3

import json
import sys
import os
import stat
import subprocess
import tempfile
import time

SYNOPSIS="""\
Usage: diskhdr <JSONFILE|help> [COMMAND] [ARG]...
Tool to format disk or file specified by a json file.

Without COMMAND it will just check json file or display this help.

COMMANDS:
  format <FILE|BLOCKDEVICE>...
  mount <FSARCH_IDX> <FILE|BLOCKDEVICE> <MOUNTPOINT_PATH>
  umount <FSARCH_IDX> <FILE|BLOCKDEVICE>
  fstab <FSARCH_IDX> <FILE|BLOCKDEVICE>
  swapsize <DISK_IDX>
  minsize <DISK_IDX>
  mounts <DISK_IDX>
  help
"""

CMD_lIST = ["format", "mount", "mounts", "umount", "fstab", "swapsize", "minsize"]

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
    if str_is_help(sys.argv[2]):
        log_out(SYNOPSIS)
        sys.exit(0)
    elif "--help" in sys.argv or "-help" in sys.argv or "-h" in sys.argv:
        log_out(SYNOPSIS)
        sys.exit(0)
    elif not sys.argv[2] in CMD_lIST:
        log_out(SYNOPSIS)
        die(1, "Unknown command %s" % sys.argv[2])
        sys.exit(0)

class DKHRException(Exception):
    def __init__(self, message):
        super(DKHRException, self).__init__(message)

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

    return int(size_str)

def dkhr_check_partitions_size(partitions):
    infinite_size_found = False
    for partinfo in partitions:
        if not "size" in partinfo.keys():
            if infinite_size_found:
                return False
            infinite_size_found = True
    return True

def dkhr_check_disk_repr(disk_repr):
    if not "table" in disk_repr.keys():
        raise DKHRException("check disk: the key 'table' missing")

    if not "parts" in disk_repr.keys():
        raise DKHRException("check disk: the key 'parts' missing")

    if len(disk_repr["parts"]) == 0:
        raise DKHRException("check disk: No partitions")

    if disk_repr["table"] == "msdos":
        if len(disk_repr["parts"]) > 4:
            raise DKHRException("check disk: handle a maximum of 4 in msdos table (count:%d)"
                                % len(disk_repr["parts"]))
        # for part in disk_repr["parts"]:
        #     if "partname" in part.keys():
        #         log_err("check disk: msdos do not handle partition name")
        for part in disk_repr["parts"]:
            if not "type" in part.keys():
                DKHRException("check part: the key 'type' missing")
    elif disk_repr["table"] == "gpt":
        if len(disk_repr["parts"]) > 128:
            raise DKHRException("check disk: Maximum partitions in gpt table is 128 (count:%d)"
                                % len(disk_repr["parts"]))
    else:
        raise DKHRException("check disk: Unhandled partition table %s" % disk_repr["table"])

    for part in disk_repr["parts"]:
        if not "type" in part.keys():
            DKHRException("check part: the key 'type' missing")

    if not dkhr_check_partitions_size(disk_repr["parts"]):
        raise DKHRException("check disk: Only one partition can have infinite size (some size missing)")

def dkhr_get_min_size(disk_repr):
    size_in_mo = 0
    for partinfo in disk_repr["parts"]:
        if "size" in partinfo.keys():
            size_in_mo += get_mo_size(partinfo["size"])
    return size_in_mo

def check_disks_repr_list(disks_list):
    if len(disks_list) == 0:
        raise DKHRException("check disks: No disk found")

    if len(disks_list) != 1:
        raise DKHRException("check disks: Only one disk is currently available")

    dkhr_check_disk_repr(disks_list[0])

def check_systems_repr_list(systems_list, disks_list):
    check_disks_repr_list(disks_list)

    if len(systems_list) == 0:
        raise DKHRException("check systems: No system found")

    if len(systems_list) != 1:
        raise DKHRException("check systems: Only one system is currently available")

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
except DKHRException as e:
    die(1, "Check error\n%s" % e)

if len(sys.argv) < 3:
    sys.exit(0)

if os.geteuid() != 0:
    die(1, "Commands need root privilegies")

def gen_parted_create_cmd(disk_repr, path_dst):
    parted_cmd = "parted -s " + path_dst + " -- mktable " + disk_repr["table"]

    last_offset = 0
    part_idx = 0
    size_missing = False

    for part in disk_repr["parts"]:
        if "size" in part.keys():
            # !!!!! Need a function
            end_offset = last_offset + get_mo_size(part["size"])
            if disk_repr["table"] == "msdos":
                parted_cmd += " mkpart primary {type} {start} {end}".format(type=part["type"],
                                                                            start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                            end="%dMB" % end_offset)
            else:# if disk_repr["table"] == "gpt":
                end_offset = last_offset + get_mo_size(part["size"])
                if "partname" in part.keys():
                    parted_cmd += " mkpart {partname} {type} {start} {end}".format(partname=part["partname"],
                                                                                   type=part["type"],
                                                                                   start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                                   end="%dMB" % end_offset)
                else:
                    parted_cmd += " mkpart {type} {start} {end}".format(type=part["type"],
                                                                        start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                        end="%dMB" % end_offset)
            last_offset = end_offset
        else:
            size_missing = True
            break
        part_idx += 1

    if size_missing:
        if (len(disk_repr["parts"]) - 1) == part_idx:
            if disk_repr["table"] == "msdos":
                parted_cmd += " mkpart primary {type} {start} {end}".format(type=part["type"],
                                                                            start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                            end="100%")
            else:# if disk_repr["table"] == "gpt":
                if "partname" in part.keys():
                    parted_cmd += " mkpart {partname} {type} {start} {end}".format(partname=part["partname"],
                                                                                   type=part["type"],
                                                                                   start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                                   end="100%")
                else:
                    parted_cmd += " mkpart {type} {start} {end}".format(type=part["type"],
                                                                        start="0%" if last_offset == 0 else "%dMB" % last_offset,
                                                                        end="100%")
        else:
            raise DKHRException("gen_parted_create_cmd: infinite partition not at end will coming")
    return parted_cmd

def wait_path(path):
    count=20
    while count > 0:
        if os.path.exists(path):
            return
        count -= 1
        time.sleep(.5)
    raise DKHRException("wait_path: timeout on %s" % path)

def gen_mkfs_cmd(part_list, blk_prefix):
    mkfs_cmd_list = []
    part_num = 1
    for part in part_list:
        part_path = blk_prefix + "%d" % part_num
        wait_path(part_path)
        if part["type"] == "fat32":
            mkfs_cmd_list.append("mkfs.fat -F32 %s > /dev/null 2>&1" % part_path)
        elif part["type"] == "ext4":
            mkfs_cmd_list.append("mkfs.ext4 -F %s > /dev/null 2>&1" % part_path)
        else:# elif part["type"] == "linux-swap":
            mkfs_cmd_list.append("mkswap -f %s > /dev/null 2>&1" % part_path)
        part_num += 1
    return " && ".join(mkfs_cmd_list)

def kpartx_file(filepath):
    try:
        kpartx_stdout = subprocess.check_output("kpartx -av %s" % filepath,
                                                shell=True)
        kpartx_stdout_list = kpartx_stdout.decode("ascii").split(" ")
        if kpartx_stdout_list[0] != "add" or kpartx_stdout_list[1] != "map":
            raise DKHRException("kpartx_file: kpartx output unexpected")
        loop_num = int(kpartx_stdout_list[2].split("p")[1])
        # log_msg("file {file} mapped via kpartx on /dev/loop{num} (and /dev/mapper/loop{num}p*)".format(file=filepath, num=loop_num))
        return loop_num
    except:
        raise DKHRException("kpartx_file: Unhandled error")

DST_BLOCK = 0
DST_FILE = 1

def check_dstpath(dstpath):
    if not os.path.exists(dstpath):
        dstpath1 = os.path.realpath(dstpath + "1")
        if not os.path.exists(dstpath1):
            mode = os.stat(dstpath1).st_mode
            if stat.S_ISBLK(mode):
                return DST_BLOCK
        raise DKHRException("%s does not exist" % dstpath)

    mode = os.stat(dstpath).st_mode
    if stat.S_ISREG(mode):
        return DST_FILE
    elif stat.S_ISBLK(mode):
        return DST_BLOCK
    else:
        raise DKHRException("Unhandled type of file (%s)" % dstpath)


def set_kpartx_if_needed(dst_path):
    if check_dstpath(dst_path) == DST_FILE:
        loop_num = kpartx_file(cmd_n_args[2])
        return "/dev/mapper/loop%dp" % loop_num
    return None

cmd_n_args = sys.argv[2:]
system_repr_list = diskhdr_obj["systems"]
disks_list = diskhdr_obj["disks"]

using_kpartx = False

def create_mountpoints(system_repr, disks_list, blk_prefix_list):
    if len(disks_list) != len(blk_prefix_list):
        raise DKHRException("create_mountpoints: disk list and block list number mismatch")
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
    print("mount {blk} {mount}".format(blk=blkpath,
                                       mount=mountpoint))
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
if command == "format":
    if len(cmd_n_args) > 2:
        log_out(SYNOPSIS)
        die(1, "Wrong number of arguments (multiple device not yet supported)")
    dst_path = cmd_n_args[1]
    if check_dstpath(dst_path) == DST_FILE:
        using_kpartx = True
    else:
        dst_path = os.path.realpath(dst_path)
    format_cmd = gen_parted_create_cmd(disks_list[0], dst_path)
    format_cmd += " && partprobe %s" % dst_path
    log_msg(format_cmd)
    if os.system(format_cmd) != 0:
        die(1, "Format fail")
    if using_kpartx:
        loop_num = kpartx_file(dst_path)
        try:
            blk_prefix = "/dev/mapper/loop%dp" % loop_num
            mkfs_cmd = gen_mkfs_cmd(disks_list[0]["parts"], blk_prefix)
            log_msg(mkfs_cmd)
            if os.system(mkfs_cmd) != 0:
                os.system("kpartx -d %s" % dst_path)
                die(1, "%s: mkfs fail" % command)
            create_mountpoints(system_repr_list[0], disks_list, [blk_prefix])
        except DKHRException as e:
            log_err("Unable to create filesystem\n%s" % e)
        finally:
            os.system("kpartx -d %s" % dst_path)
    else:
        mkfs_cmd = gen_mkfs_cmd(disks_list[0]["parts"], dst_path)
        # get a better solution (part probe check etc)
        mkfs_cmd = "sleep 1 && " + mkfs_cmd
        # log_msg("Running:\n%s" % mkfs_cmd)
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

    dst_path = cmd_n_args[2]

    if command == "mount":
        blk_prefix = set_kpartx_if_needed(dst_path)
        if blk_prefix:
            using_kpartx
        else:
            blk_prefix = os.path.realpath(dst_path)
        if len(cmd_n_args) != 4:
            if using_kpartx:
                os.system("kpartx -d %s" % dst_path)
            log_out(SYNOPSIS)
            die(1, "Wrong number of arguments")
        mount_point = cmd_n_args[3]
        mount_system(system_repr_list[system_num], [blk_prefix], mount_point)
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
        blk_prefix = set_kpartx_if_needed(dst_path)
        if blk_prefix:
            dump_fstab(system_repr_list[system_num], disks_list, [blk_prefix])
            os.system("kpartx -d %s > /dev/null 2>&1" % dst_path)
            using_kpartx
        else:
            dump_fstab(system_repr_list[system_num], disks_list, [os.path.realpath(dst_path)])
    else:
        die(1, "Unknown command %s" % command)
