/**
* Create The Utility / Management Schema and Objects
*
* @author Shaun Thomas <sthomas@peak6.com>
* @package: tools
* @subpackage: ddl
*/

CREATE SCHEMA IF NOT EXISTS utility;

-- The util_exec role will act as the grant target for all of these objects.
-- This way, usage can be granted by following the role.

DO $$
BEGIN
  PERFORM 1 FROM pg_roles WHERE rolname = 'util_exec';

  IF NOT FOUND THEN
    EXECUTE 'CREATE ROLE util_exec';
  END IF;
END;
$$ LANGUAGE plpgsql;

GRANT USAGE ON SCHEMA utility TO util_exec;

ALTER DEFAULT PRIVILEGES
  FOR USER postgres
   IN SCHEMA utility
GRANT ALL ON TABLES TO util_exec;

ALTER DEFAULT PRIVILEGES
  FOR USER postgres
   IN SCHEMA utility
GRANT USAGE ON SEQUENCES TO util_exec;

ALTER DEFAULT PRIVILEGES
  FOR USER postgres
   IN SCHEMA utility
GRANT EXECUTE ON FUNCTIONS TO util_exec;

-- Switch to the utility schema for all subsequent work.

SET search_path TO utility;

--------------------------------------------------------------------------------
-- CREATE TABLES
--------------------------------------------------------------------------------

/* Tables are supplied by elephaas project, and these versions might
   not be up to date */

CREATE TABLE IF NOT EXISTS ele_environment
(
  environment_id  SERIAL NOT NULL PRIMARY KEY,
  env_name        VARCHAR(40) NOT NULL,
  env_descr       text NOT NULL,
  created_dt      TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
  modified_dt     TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS ele_herd
(
    herd_id         SERIAL NOT NULL PRIMARY KEY,
    environment_id  INTEGER NOT NULL REFERENCES ele_environment (environment_id),
    herd_name       VARCHAR NOT NULL,
    herd_descr      VARCHAR,
    db_port         INTEGER NOT NULL,
    pgdata          VARCHAR NOT NULL,
    vhost           VARCHAR NOT NULL,
    created_dt      TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
    modified_dt     TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS ele_server
(
    server_id       SERIAL NOT NULL PRIMARY KEY,
    hostname        VARCHAR(40) NOT NULL,
    created_dt      TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
    modified_dt     TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
    environment_id  INTEGER REFERENCES ele_environment (environment_id)
);

CREATE INDEX idx_server_environment_id ON ele_server (environment_id);

CREATE TABLE IF NOT EXISTS ele_instance
(
    instance_id   SERIAL NOT NULL PRIMARY KEY,
    version       VARCHAR(10) NOT NULL,
    local_pgdata  VARCHAR(100) NOT NULL,
    xlog_pos      BIGINT,
    is_online     BOOLEAN NOT NULL,
    created_dt    TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
    modified_dt   TIMESTAMP WITHOUT TIME ZONE DEFAULT now() NOT NULL,
    herd_id       INTEGER NOT NULL REFERENCES ele_herd (herd_id),
    server_id     INTEGER NOT NULL REFERENCES ele_server (server_id),
    master_id     INTEGER REFERENCES ele_instance (instance_id)
);

CREATE INDEX idx_instance_server_id ON ele_instance (server_id);
CREATE INDEX idx_instance_herd_id ON ele_instance (herd_id);
CREATE INDEX idx_instance_master_id ON ele_instance (master_id);

--------------------------------------------------------------------------------
-- CREATE VIEWS
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_dr_pairs AS
SELECT DISTINCT ON (herd_id)
       r.herd_id, r.instance_id, r.master_id, r.server_id,
       round(abs(coalesce(p.xlog_pos, 0) - coalesce(r.xlog_pos, 0)) / 1024.0, 1) AS mb_lag,
       h.vhost
  FROM ele_instance r
  JOIN ele_instance p ON (p.instance_id = r.master_id)
  JOIN ele_herd h ON (h.herd_id = r.herd_id)
 WHERE r.is_online
   AND r.master_id IS NOT NULL
 ORDER BY herd_id, mb_lag, r.instance_id;

CREATE OR REPLACE VIEW v_flat_instance AS
SELECT i.instance_id, i.version, h.pgdata, i.local_pgdata, i.xlog_pos,
       i.is_online, h.base_name, h.herd_name, h.db_port, h.vhost,
       s.server_id, s.hostname, i.master_id,
       e.environment_id, e.env_name
  FROM utility.ele_instance i
  JOIN utility.ele_herd h USING (herd_id)
  JOIN utility.ele_environment e USING (environment_id)
  JOIN utility.ele_server s USING (server_id);


--------------------------------------------------------------------------------
-- CREATE FUNCTIONS
--------------------------------------------------------------------------------

/**
* Get Server ID Based on Hostname, or Add a New Entry
*
* Since this process cannot figure out the environment the server belongs to,
* we can only insert new servers by hostname. Because herds are tied to
* environment, we can't properly identify the herd of a new instance without
* this. Thus after this function inserts a new server, someone will need to
* log into the elephaas interface itself and apply an environment.
*
* Then the autodiscovery process will be able to register new instances.
*
* @param sHost String of the hostname we're checking/adding.
*
* @return INT server ID for listed hostname.
*/
CREATE OR REPLACE FUNCTION sp_discover_server(sHost VARCHAR)
RETURNS INT
AS $$
DECLARE
  nServer INT;
BEGIN
  SELECT INTO nServer server_id
    FROM utility.ele_server
   WHERE hostname = lower(sHost);

  -- Insert the server if it wasn't found before. Servers added this way
  -- will need to have an environment associated later before instances
  -- can be auto-discovered here.

  IF NOT FOUND THEN
    INSERT INTO utility.ele_server (hostname)
    VALUES (lower(sHost))
    RETURNING server_id INTO nServer;
  END IF;

  RETURN nServer;

END;
$$ LANGUAGE plpgsql;


/**
* Get Herd ID Based on Name, Port, and Environment ID.
*
* @param sHost String of the herd name we're checking.
* @param nPort Port number this herd uses for connecting.
* @param nEnv Environment ID; necessary to differentiate similar herds.
*
* @return INT Herd ID we're searching for.
*/
CREATE OR REPLACE FUNCTION sp_get_herd(sName VARCHAR, nPort INT, nEnv INT)
RETURNS INT
AS $$
  SELECT herd_id
    FROM utility.ele_herd
   WHERE base_name = lower(sName)
     AND db_port = nPort
     AND environment_id = nEnv;
$$ LANGUAGE SQL;


/**
* Register instance information or changes
*
* When remote systems call this function to register instances, we want to
* do two things:
*
* - Deflect duplicate inserts.
* - Catch relevant changes
*
* In effect, we'll track new instances the first time they're encountered,
* and modify existing instances with newly updated details as the xlog
* position moves, or something gets shut down, for example.
*
* All of the "DEFAULT" parameters is optional because there are so many of
* them. The best use of this function is to call it with named arguments
* and only pass data that has changed since the last call. The presumption
* here is that only automated systems will invoke this.
*/
CREATE OR REPLACE FUNCTION sp_instance_checkin(
  sHerd VARCHAR,
  sHost VARCHAR,
  nPort INT,
  sVer VARCHAR DEFAULT NULL,
  bOnline BOOLEAN DEFAULT NULL,
  sDataDir VARCHAR DEFAULT NULL,
  sMasterHost VARCHAR DEFAULT NULL,
  nXlog BIGINT DEFAULT NULL
)
RETURNS VOID
AS $$
DECLARE
  rInst  RECORD;
  rHerd  RECORD;

  nLead  INT;
  nSrv   INT;
  sData  VARCHAR;
BEGIN
  -- Look for any existing instances. If we find one, this will need to be an
  -- update. Lock accordingly. We do this first to avoid possible race
  -- conditions.

  SELECT INTO rInst *
    FROM utility.v_flat_instance
   WHERE hostname = sHost
     AND base_name = sHerd
     FOR UPDATE;

  -- If there's master information, look up the instance of the referring
  -- reference.

  IF sMasterHost IS NOT NULL THEN
    SELECT INTO nLead instance_id
      FROM utility.v_flat_instance
     WHERE hostname = sMasterHost
       AND base_name = sHerd;
  END IF;

  -- If this instance doesn't exist, dump all of the fields into the tracking
  -- table unchanged. Subsequent registration calls will fall through to the
  -- next section.

  IF rInst.instance_id IS NULL THEN

    -- Try to get the existing herd ID, Server ID. If we can't find either
    -- of these, do not capture the instance. More needs to be done in the
    -- admin interface to describe the environment or create a representative
    -- herd.

    nSrv = utility.sp_discover_server(sHost);

    SELECT INTO rHerd herd_id, pgdata
      FROM utility.ele_herd h
     WHERE base_name = lower(sHerd)
       AND db_port = nPort
       AND environment_id = (SELECT environment_id FROM utility.ele_server
                              WHERE server_id = nSrv);

    IF nSrv IS NULL OR NOT FOUND THEN
      RETURN;
    END IF;

    sData = '';
    IF sDataDir != rHerd.pgdata THEN
      sData = sDataDir;
    END IF;

    INSERT INTO utility.ele_instance (
        version, local_pgdata, is_online, herd_id, server_id, master_id
    ) VALUES (
        sVer, sData, bOnline, rHerd.herd_id, nSrv, nLead
    );

    RETURN;
  END IF;

  -- Of the mentioned relevant fields in our header, only update when those
  -- elements change. Normally we'd ignore the pgdata entry, but until our
  -- systems adhere to the recommended SOP, many of these could change.
  -- Because the version may depend on the instance being up to get the
  -- full value, we'll use the highest between the two.

  IF (bOnline, nLead, sVer, sDataDir, nXlog)
       IS DISTINCT FROM
     (rInst.is_online, rInst.master_id, rInst.version, rInst.pgdata, rInst.xlog_pos)
  THEN
    UPDATE utility.ele_instance
       SET is_online = COALESCE(bOnline, rInst.is_online),
           master_id = COALESCE(nLead, rInst.master_id),
           version = array_to_string(
                       GREATEST(
                         string_to_array(rInst.version, '.')::INT[],
                         string_to_array(sVer, '.')::INT[]
                       ), '.'
                     ),
           local_pgdata = COALESCE(sData, rInst.local_pgdata),
           xlog_pos = COALESCE(nXlog, rInst.xlog_pos)
     WHERE instance_id = rInst.instance_id;
  END IF;

  RETURN;

END;
$$ LANGUAGE plpgsql;


/**
* Update created/modified timestamp automatically
*
* This function maintains two metadata columns on any table that uses
* it in a trigger. These columns include:
*
*  - created_dt  : Set to when the row first enters the table.
*  - modified_at : Set to when the row is ever changed in the table.
*
* @return object  NEW
*/
CREATE OR REPLACE FUNCTION PUBLIC.sp_audit_stamps()
RETURNS TRIGGER AS
$$
BEGIN

  -- All inserts get a new timestamp to mark their creation. Any updates should
  -- inherit the timestamp of the old version. In either case, a modified
  -- timestamp is applied to track the last time the row was changed.

  IF TG_OP = 'INSERT' THEN
    NEW.created_dt = now();
  ELSE
    NEW.created_dt = OLD.created_dt;
  END IF;

  NEW.modified_dt = now();

  RETURN NEW;

END;
$$ LANGUAGE plpgsql;

REVOKE EXECUTE
    ON FUNCTION PUBLIC.sp_audit_stamps()
  FROM PUBLIC;

GRANT EXECUTE
   ON FUNCTION PUBLIC.sp_audit_stamps()
   TO util_exec;

--------------------------------------------------------------------------------
-- CREATE TRIGGERS
--------------------------------------------------------------------------------

CREATE TRIGGER t_ele_instance_timestamp_b_iu
BEFORE INSERT OR UPDATE ON ele_instance
   FOR EACH ROW EXECUTE PROCEDURE PUBLIC.sp_audit_stamps();

CREATE TRIGGER t_ele_herd_timestamp_b_iu
BEFORE INSERT OR UPDATE ON ele_herd
   FOR EACH ROW EXECUTE PROCEDURE PUBLIC.sp_audit_stamps();

CREATE TRIGGER t_ele_server_timestamp_b_iu
BEFORE INSERT OR UPDATE ON ele_server
   FOR EACH ROW EXECUTE PROCEDURE PUBLIC.sp_audit_stamps();

CREATE TRIGGER t_ele_environment_timestamp_b_iu
BEFORE INSERT OR UPDATE ON ele_environment
   FOR EACH ROW EXECUTE PROCEDURE PUBLIC.sp_audit_stamps();
