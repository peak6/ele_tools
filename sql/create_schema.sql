/**
* Create The Utility / Management Schema and Objects
*
* By default, ElepHaaS uses the utility schema. We will assume the same.
* Maybe at some point in the future, we will move several of the support
* views and functions into an extension and deprecate this entire file.
* As such, this file only defines some loose functions that the CLI tools
* might need to invoke on the primary ElepHaaS server. Tables, views or
* other permanent fixtures should be viewed directly in the ElepHaaS
* project.
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

GRANT ALL
   ON ALL TABLES IN SCHEMA utility
   TO util_exec;

GRANT ALL
   ON ALL SEQUENCES IN SCHEMA utility
   TO util_exec;

-- Switch to the utility schema for all subsequent work.

SET search_path TO utility;

--------------------------------------------------------------------------------
-- CREATE TABLES / VIEWS 
--------------------------------------------------------------------------------

-- Nothing here. See ElepHaaS project

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
     AND db_port = nPort
     FOR UPDATE;

  -- If there's master information, look up the instance of the referring
  -- reference.

  IF sMasterHost IS NOT NULL THEN
    SELECT INTO nLead instance_id
      FROM utility.v_flat_instance
     WHERE hostname = sMasterHost
       AND base_name = sHerd
       AND db_port = nPort;
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
