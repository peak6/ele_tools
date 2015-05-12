
import re
import getpass
import subprocess

from distutils import spawn
from PGUtil.Instance import Instance

class Environment(object):
    """ Mine a local server environment for PostgreSQL cluster instances
    
    This class is designed to delve into the current environment of a 
    UNIX-based system and locate PostgreSQL instances using various methods.
    After that, it will obtain as much information about each instance
    so they can be sent commands, inventoried, or monitored. It's a generic
    utility structure.
    """

    instances = {}

    def __init__(self):
        """ Initialize by checking the current environment for PG instances
        
        This function currently only tries to use pg_lsclusters to locate
        running instances, thus works best with Debian/Ubuntu variants. If
        this is not found, it reverts to assuming a single instance is running
        and tries to inventory it based on PG defaults.
        
        Later versions of this may be more intelligent about this process.
        """

        # If this is not a Debian/Ubuntu system, try to register the default
        # PostgreSQL port connection. Assume the instance is offline, as the
        # instance constructor will revert if that isn't the case.

        if not spawn.find_executable('pg_lsclusters'):
            self.instances['main'] = Instance(
                name = 'main', port = 5432, user = getpass.getuser(),
                online = True
            )
            return

        # Otherwise, get a list of all running instance ports. Attempt to
        # register each one according to pg_lscluster output fields.

        output = subprocess.check_output(
            ('pg_lsclusters', '--no-header'),
            stderr = subprocess.STDOUT
        )

        for line in output.split('\n'):
            if not line:
                continue

            fields = re.split('\s+', line)
            (ver, name, port, status, user, pgdata) = fields[:6]

            self.instances[name] = Instance(
                name = name,
                port = port,
                user = user,
                pgdata = pgdata,
                online = ('online' in status) and True or False,
                role = ('recovery' in status) and 'slave' or 'master'
            )


# Set up the object and external callables.

__all__ = ['Environment']


