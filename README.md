What is PGUtil
==============

PGUtil is a small library that provides CLI tools and Python class libraries for generic API manipulation of PostgreSQL structures both local and remote.

Currently this library is focused on local instance manipulation. To take full advantage, use SSH tunnels to call them on remote systems.

Installation Instructions
=========================

Installing the PGUtil libraries and scripts is simple enough:

    python setup.py install

However, we also recommend two subsequent steps must also be applied to enable remote invocation of these utilities.

Installing Access
-----------------

These tools are designed to run as the user that owns the database files, as they often need to read or modify files within the PGDATA directory itself. That also applies to database access, whenever possible. As such, we strongly encourage the use of local `peer` authentication for this user, and SSH keys to enable invocation.

Place the following line in `pg_hba.conf` for every local instance:

    local  all  check_mk  peer

Alternatively for password access, create a `.pgpass` file with these contents:

    localhost:*:*:postgres:whatever


Installing Administration Schema
--------------------------------

These libraries also provide a schema for administration purposes. Some CLI tools might report to this system, and others might use it as a point of reference. To install this schema, execute the `create_schema.sql` source script on the desired administrative database target as a database superuser:

    psql -f create_schema.sql util

To grant usage to these objects to non superusers, grant access using the `util_exec` role:

    CREATE USER util_user WITH PASSWORD 'whatever';
    GRANT util_exec TO util_user;


Usage Instructions
==================

There is currenly only one CLI tool that does any work. It will search for local PostgreSQL instances and report them to a remote system.

pgutil_report
-------------

This utility should be executed as the same user that owns the database files, as it needs access to the PGDATA directory. Its only purpose is to communicate with an upstream system and tell it which instances exist locally, and their current status.

configuring pgutil_report
-------------------------

By default, the configuration file resides in `/etc/pg_util/report.ini`. To configure for regular reports, create this file and set several fields in the `[Local]` section. Set all fields necessary to connect to the remote administration system.

The fields have the following meanings:

* **db_host**: Hostname of the remote admin system.
* **db_port**: Port of the instance for the remote admin system. Default: 5432.
* **db_user**: Username to use while connecting to the remote system. Default: util_user.
* **db_name**: Name of the database where reports should be sent. Default: utility.

Note there is no password field. This is by intention to encourage using `.pgpass` files instead. Create a `.pgpass` file so this user can connect to the remote administration system.

