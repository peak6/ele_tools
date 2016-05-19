#!/usr/bin/env python

from EleTools import scripts
import EleTools as util

import os
import sys
import socket
import logging
import pickle

def main():
    parser = scripts.get_arg_parser('Transmit Local PG Instance Report')
    parser.set_defaults(config='/etc/ele_tools/report.ini')

    args = parser.parse_args()
    scripts.init_logging(args.log, args.debug)
    sys.excepthook = scripts.handler

    # For now, this tool only seeks connection to an external system to report
    # the instances.

    sections = {
        'Local': {
            'db_host': '',
            'db_port': '5432',
            'db_user': 'util_user',
            'db_name': 'utility',
        }
    }
    conf = util.Config(args.config, sections)

    # Loop through all of the known instances and call the registration
    # function on each. This assumes that the target system has the
    # requisite stored procedures and/or tables.

    env = util.Environment()
    host = socket.gethostname()

    if args.debug:
        logging.debug("Transmitting instances to %s", conf.db_host)

    conn = util.db_connect(conf.db_host, conf.db_user, conf.db_name,
        conf.db_port)
    cur = conn.cursor()

    for inst in env.instances.values():

        if inst.invalid:
            continue;

        curr_info = dict(
            sHost = host, sHerd = inst.name, nPort = inst.port,
            sVer = inst.version, bOnline = inst.online,
            sDataDir = inst.pgdata, sMasterHost = inst.master_host,
            nXlog = inst.xlog_pos
        )

        # To avoid overloading the remote admin system, only transmit data
        # when at least one optional field has changed since the last
        # successful transmission. We can quickly find any differences
        # by checking against our cache, if available. The stored
        # procedure will do an INSERT or UPDATE based on whether this
        # instance is listed already or not, so we can't know which is
        # happening. Thus, we have to send all information whenever a
        # change is detected.

        cache_file = os.path.join(os.sep, 'tmp',
            'ele_tools.%s.%s.cache' % (inst.name, inst.port) 
        )

        if os.path.exists(cache_file):
            prev_info = pickle.load(open(cache_file, 'rb'))
            if curr_info == prev_info:
                if args.debug:
                    logging.debug(
                        " * %s hasn't changed since last xmit.", inst.name
                    )
                continue

        # Now transmit the various elements. Build the function call based
        # on the fields remaining in the argument list.

        if args.debug:
            logging.debug(" * " + ', '.join(str(x) for x in (
                host, inst.name, inst.port, inst.version, inst.role,
                inst.user, inst.online, inst.pgdata, inst.master_host,
                inst.master_port, inst.xlog_pos))
            )

        # We have the parameter list, but we need to build the query string.
        # Since we have a convenient dictionary, build it based on dictionary
        # string substitution. Then we can cache the current information for
        # the next iteration; any problems will prevent the cache, so we can
        # try again later.

        sql_params = ', '.join(
            [k + ':=%(' + k + ')s' for k in curr_info.keys()]
        )
        SQL = "SELECT utility.sp_instance_checkin(" + sql_params + ')'

        cur.execute(SQL, curr_info)

        pickle.dump(curr_info, open(cache_file, 'wb'))

    conn.close()

    if args.debug:
        logging.debug("Transmission complete")


if __name__ == "__main__":
    main()
