#!/usr/bin/env python

from PGUtil import scripts
import PGUtil as util

import sys
import socket
import logging

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
        if args.debug:
            logging.debug(" * " + ', '.join(str(x) for x in (
                host, inst.name, inst.port, inst.version, inst.role,
                inst.user, inst.online, inst.pgdata, inst.master_host,
                inst.master_port)))

        cur.execute(
            "SELECT utility.sp_instance_checkin("
            " %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (host, inst.name, inst.port, inst.version, inst.role, inst.user,
             inst.online, inst.pgdata, inst.master_host, inst.master_port)
        )

    conn.close()

    if args.debug:
        logging.debug("Transmission complete")


if __name__ == "__main__":
    main()
