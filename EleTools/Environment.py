
import re
import os
import pwd
import getpass
import subprocess

from glob import glob
from distutils import spawn
from EleTools.Instance import Instance

class Environment(object):
    """ Mine a local server environment for PostgreSQL cluster instances

    This class is designed to delve into the current environment of a 
    UNIX-based system and locate PostgreSQL instances using various methods.
    After that, it will obtain as much information about each instance
    so they can be sent commands, inventoried, or monitored. It's a generic
    utility structure.
    """

    detect = {}
    instances = {}

    socket_dirs = [
        '/tmp',
        '/var/run/postgresql',
    ]

    __blank = {
        'name': 'main', 'port': 5432, 'pgdata': '', 'online': False,
        'user': 'postgres', 'online': False, 'role': 'master', 
    }


    def discover(self):
        """ Check the current environment for PG instances

        Use any known socket directories, lock locations, distribution-based
        or otherwise influential methods for detecting Postgres instances on
        the local system. Use that information to fill an 'instances'
        attribute with Instance objects for each port detected.
        """

        self.__try_sockets()
        self.__try_lsclusters()

        for port, inst_env in self.detect.items():
            self.instances[port] = Instance(**inst_env)


    def __try_sockets(self):
        """ Look for Postgres instances based on running socket/lock files.

        This function only works on running Postgres instances, unfortunately.
        While running, Postgres instances leave a socket file in a directory
        (usually /tmp) along with a file detailing some information about the
        instance on the reserved port.
        """

        for sock in self.socket_dirs:
            if not os.path.exists(sock):
                continue

            for lock_file in glob(os.path.join(sock, '.s.PGSQL.*.lock')):
                with open(lock_file) as x: lock_data = x.readlines()

                pgport = lock_data[3].strip()

                self.detect[pgport] = self.__blank.copy()

                inst_conf = {
                    'port': pgport,
                    'pgdata': lock_data[1].strip(),
                    'user': pwd.getpwuid(os.stat(lock_file).st_uid).pw_name,
                    'online': True
                }

                self.detect[pgport].update(inst_conf)


    def __try_lsclusters(self):
        """ Look for Postgres instances on a Debian-derived system.

        This function tries to use pg_lsclusters to locate running instances,
        thus works with Debian/Ubuntu variants. 
        """

        # If this is not a Debian/Ubuntu system, there's nothing to do here.

        if not spawn.find_executable('pg_lsclusters'):
            return

        # Otherwise, get a list of all running instance ports. Attempt to
        # register each one according to pg_lscluster output fields. We also
        # need to separate the instances by version, since that's how these
        # systems organize installed clusters: name + version.

        output = subprocess.check_output(
            ('pg_lsclusters', '--no-header'),
            stderr = subprocess.STDOUT
        )

        for line in output.split('\n'):
            if not line:
                continue

            fields = re.split('\s+', line)
            (ver, name, port, status, user, pgdata) = fields[:6]

            if port not in self.detect:
                self.detect[port] = self.__blank.copy()

            inst_conf = {
                'name': name,
                'port': port,
                'user': user,
                'pgdata': pgdata,
                'online': ('online' in status) and True or False,
                'role': ('recovery' in status) and 'slave' or 'master'
            }

            self.detect[port].update(inst_conf)


# Set up the object and external callables.

__all__ = ['Environment']


