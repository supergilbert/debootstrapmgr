#!/usr/bin//python3

import sys
import re

SYNOPSIS="""\
Usage: %s <SOURCES_LIST_PATH> <SOURCE_ENTRY_INDEX> <KEY>

KEY=<type|option|uri|suite|components>""" % sys.argv[0]

if "-h" in sys.argv or "help" in sys.argv or "--help" in sys.argv:
    print(SYNOPSIS)
    sys.exit(0)

def read_apt_sources_list(sources_list_path):
    sources_str = open(sources_list_path, "r").read()
    ret_list = []
    for line in sources_str.split("\n"):
        res = re.split("\s+", line)
        if len(res) == 0 or len(res[0]) == 0 or res[0].startswith("#"):
            continue
        uri_idx = 1
        while "=" in res[uri_idx]:
            uri_idx += 1
        line_dict = {"type": res[0],
                     "options": ",".join(res[1:uri_idx]),
                     "uri": res[uri_idx],
                     "suite": res[uri_idx + 1],
                     "components": ",".join(res[uri_idx + 2:])}
        ret_list.append(line_dict)
    return ret_list

if len(sys.argv) != 4:
    print(SYNOPSIS)
    sys.exit(1)

sources_list_path = sys.argv[1]
idx = int(sys.argv[2])
key = sys.argv[3]

res = read_apt_sources_list(sources_list_path)
if idx >= len(res):
    print("Entry index out of list (idx={index} listsize={size})".format(index=idx,
                                                                          size=len(res)))
    sys.exit(1)
print(res[idx][key])
