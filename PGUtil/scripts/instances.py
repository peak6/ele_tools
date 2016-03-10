#!/usr/bin/env python

from PGUtil import scripts
import PGUtil as util

import os
import sys
import socket
import logging
import pickle

def main():
    parser = scripts.get_arg_parser('Transmit Local PG Instance Report')
    parser.set_defaults(config='/etc/pg_util/report.ini')

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
        params = curr_info

        # To avoid overloading the remote admin system, only transmit data
        # which has changed since the last successful transmission. We can
        # quickly find the differences since the last capture and build
        # what will be the parameter list to the remote proc.

        cache_file = os.path.join(os.sep, 'tmp',
            'pgutil.' + inst.name + '.cache'
        )

        if os.path.exists(cache_file):
            prev_info = pickle.load(open(cache_file, 'rb'))

            # Only keep information that's changed since last time. We also
            # need to retain the minimal parameters necessary to uniquely
            # identify this instance.

            params = {}
            for k, v in curr_info.items():
                if k in ('sHerd', 'nPort', 'sHost') or prev_info[k] != v:
                    params[k] = v

        if len(params) < 4:
            if args.debug:
                logging.debug(
                    " * " + inst.name + " hasn't changed since last xmit."
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

        sql_params = ', '.join([k + ':=%(' + k + ')s' for k in params.keys()])
        SQL = "SELECT utility.sp_instance_checkin(" + sql_params + ')'

        cur.execute(SQL, params)

        pickle.dump(curr_info, open(cache_file, 'wb'))

    conn.close()

    if args.debug:
        logging.debug("Transmission complete")


if __name__ == "__main__":
    main()
