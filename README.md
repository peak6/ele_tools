What is ele_tools
=================

Ele_tools is a small library that provides CLI tools and Python classes for generic API manipulation of local PostgreSQL structures. It is designed specifically for use with [ElepHaaS](https://github.com/peak6/elephaas) in mind, but classes are suitable for generic use. Ideally, ele_tools should be installed on all available Postgres servers, possibly through a configuration or server management system like Salt, Puppet, or CFEngine. This allows ElepHaaS to easily manage and detect Postgres instances without manual intervention.

Currently ele_tools is focused on local instance manipulation. To take full advantage, use SSH tunnels to call them on remote systems. This is how ElepHaaS invokes CLI utilities provided here.

Installation Instructions
=========================

Installing the ele_tools libraries and scripts is simple enough:

    python setup.py install

However, we also recommend two subsequent steps must also be applied to enable remote invocation of these utilities.

Installing Access
-----------------

These tools are designed to run as the user that owns the database files, as they often need to read or modify files within the PGDATA directory itself. That also applies to database access, whenever possible. As such, we strongly encourage the use of local `peer` authentication for this user, and SSH keys to enable invocation.

Place the following line in `pg_hba.conf` for every local instance:

    local  all  postgres  peer

Alternatively for password access, create a `.pgpass` file with these contents:

    localhost:*:*:postgres:whatever


Installing Administration Schema
--------------------------------

Ele_tools also provides a schema file to enhance ElepHaaS functionality. Some CLI tools might report to an upstream management server, and will reference objects contained in this file. To install, execute the `create_schema.sql` source script on the desired administrative database target as a database superuser:

    psql -f sql/create_schema.sql admin

To grant usage of these objects to non superusers, grant access using the `util_exec` role:

    CREATE USER util_user WITH PASSWORD 'whatever';
    GRANT util_exec TO util_user;


Usage Instructions
==================

There is currenly only one CLI tool that does any work. It will search for local PostgreSQL instances using `pg_lsclusters` and report them to a remote system running ElepHaaS. Future versions will likely also supply a wrapper for `pg_ctl` and remove the dependency on `pg_lsclusters` for better support of non-Debian derived OS hosts.

ele_report
----------

This utility should be executed as the same user that owns the database files, as it needs access to the PGDATA directory. Its only purpose is to communicate with an upstream system running ElepHaaS and tell it which instances exist locally, and their current status.

configuring ele_report
-------------------------

By default, the configuration file resides in `/etc/ele_tools/report.ini`. To configure for regular reports, create this file and set several fields in the `[Upstream]` section. Set all fields necessary to connect to the remote administration system.

The fields have the following meanings:

* **db_host**: Hostname of the remote admin system.
* **db_port**: Port of the instance for the remote admin system. Default: 5432.
* **db_user**: Username to use while connecting to the remote system. Default: util_user.
* **db_name**: Name of the database where reports should be sent. Default: admin.

Note there is no password field. This is by intention to encourage using `.pgpass` files instead. Create a `.pgpass` file so this user can connect to the remote administration system.

