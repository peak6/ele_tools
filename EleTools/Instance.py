
import re
import os
import socket
import getpass
import psycopg2
import psycopg2.extras


def db_connect(host, user, db, port = 5432):
    """ Connect to the indicated database and return the connection object.

    This is a helper function for utilities that need to connect to a
    database. The Instance class will enforce local connections, but reporting
    tools or other uses might need a remote connection. Make this easy.

    :param host: Hostname of the database to connect to.
    :param user: DB username to use while connecting. Needs .pgpass or peer
        auth enabled.
    :param db: Name of the database for this connection.
    :param port: Port for the target PG instance. Default: 5432.

    :retval connection: A psycopg2 connection object with autocommit enabled
        to encourage explicit transaction management if necessary.
    """

    # If the connection is localhost, don't even supply the host parameter,
    # as that will avoid a UNIX socket.

    if host == 'localhost':
        conn = psycopg2.connect(
            port = port,
            user = user,
            database = db
        )
    else:
        conn = psycopg2.connect(
            host = host,
            port = port,
            user = user,
            database = db
        )

    conn.autocommit = True

    return conn


class Instance(object):
    """ Encapsulate a PostgreSQL Database Instance
    
    List all instance databases, port, owning user, etc.
    """

    name = 'main'
    port = 5432
    user = 'postgres'
    role = 'master'
    online = False
    version = None
    pgdata = None
    master_host = None
    master_port = None
    invalid = False
    xlog_pos = None

    error = None
    databases = {}

    def __init__(self, *args, **kwargs):
        """ Set all of the basic variables and scan for active databases

        In addition to setting some important instance identifiers, this
        function will attempt to connect to any PostgreSQL databases
        it can find within the instance, except for template0 and template1.
        Any attributes beyond the sent parameters will be obtained by polling
        the environment and using various PostgreSQL CLI tools.

        :param port: Port number associated with this instance.
        :param name: Instance name. Default: main.
        :param user: Name of the system user that owns the database files.
        :param role: String identifying the role of this instance; should be
            'master' or 'slave'. Default: master.
        :param online: Boolean indicating the running status of this instance.
            Default: false
        :param pgdata: Full path to the directory where database files are
            stored. Needed to determine certain runtime elements.
        """

        for key in ('port', 'name', 'user', 'role', 'online', 'pgdata'):
            if key not in kwargs:
                continue

            val = kwargs[key]
            if key == 'port':
                val = int(kwargs[key])

            if key == 'role' and val not in ('master', 'slave'):
                continue

            if key == 'pgdata' and not val > '':
                continue

            setattr(self, key, val)

        # Since the instance might be down, try to get the version from the
        # PG_VERSION file. If that doesn't even exist, this instance is
        # invalid, and should be noted as such. If the database is up, we'll
        # get more accurate version information after connecting.

        try:
            vfile = file(os.path.join(self.pgdata, 'PG_VERSION'))
            self.version = vfile.readline().rstrip('\n')
        except:
            self.invalid = True

        # Check to see if the instance has a recovery.conf file, and what
        # might be going on in there. At the very least, grab the name
        # of the upstream master if available. If not, this is not critical,
        # so just leave these blank. That won't happen if the tool is
        # executed as the user that owns the data files themselves.

        recpath = os.path.join(self.pgdata, 'recovery.conf')

        if os.path.exists(recpath) and os.access(recpath, os.R_OK):
            recovery = file(recpath)

            for line in recovery:
                if line.find('primary_conninfo') != 0:
                    continue

                self.role = 'slave'

                # Because the host and port parameters are optional if this is
                # a local slave, or the master is on the default port, set them
                # explicitly to default local values and override from 
                # recovery.conf values.

                self.master_host = socket.gethostname()
                self.master_port = 5432

                info = re.search('host\s?=\s?([\w\.-_]+)', line)
                if info:
                    host = info.groups(1)[0]
                    if host != 'localhost':
                        self.master_host = host

                info = re.search('port\s?=\s?(\d+)', line)
                if info:
                    self.master_port = int(info.groups(1)[0])

        # Finally, try to connect to all of the databases in the instance
        # and record those connections for later use.

        self.__connect()


    def __connect(self):
        """ Connect to all instance databases for potential script execution

        Attempt to connect to our instance port using the current user to
        the 'template1' database which must exist. We use the local user
        assuming there is a `.pgpass` file that handles passwords for us,
        or peer authentication is enabled.
        
        Once this is done, we will find all databases in the instance and
        create a connection to each. These connections can be used to poll
        for further instance information, or retained for script invocation.
        """

        try:
            temp_conn = db_connect('localhost', getpass.getuser(),
                'template1', self.port)

            self.online = True

            # Now that we're connected, get the most up-to-date system
            # version. This should override the value obtained from PG_VERSION
            # since it's more precise.

            cur = temp_conn.cursor()
            SQL = "SELECT substring(version() FROM '\d+(?:\.\d+){1,2}')"
            cur.execute(SQL)
            self.version = cur.fetchone()[0]

            # Capture the xlog position so callers can use the information
            # to calculate replication lag.

            usefunc = 'pg_current_xlog_location()'
            if self.role == 'slave':
                usefunc = 'pg_last_xlog_replay_location()'

            SQL = "SELECT pg_xlog_location_diff(" + usefunc + ", '0/00000000')"
            cur.execute(SQL)
            self.xlog_pos = cur.fetchone()[0]

            # Try to connect individually to each database. At the end, we'll
            # be throwing away the temporary connection.

            cur = temp_conn.cursor()
            cur.execute("SELECT datname FROM pg_stat_database \
                          WHERE datname NOT LIKE 'template_'")

            for row in cur:
                conn = db_connect('localhost', getpass.getuser(),
                    row[0], self.port)

                self.databases[row[0]] = conn

            temp_conn.close()

        # In the case an exception happened above, either the instance went
        # down, or we can't communicate successfully with it. In any case,
        # mark that this instance is not online so the caller can ignore it.

        except psycopg2.OperationalError, e:
            self.error = e
            self.online = False


# Set up the object and external callables.

__all__ = ['Instance', 'db_connect']
