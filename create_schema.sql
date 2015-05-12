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

-- Switch to the utility schema for all subsequent work.

SET search_path TO utility;

--------------------------------------------------------------------------------
-- CREATE TABLES
--------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS util_instance
(
  instance_id  SERIAL   PRIMARY KEY,
  db_host      VARCHAR  NOT NULL,
  instance     VARCHAR  NOT NULL,
  db_port      INT      NOT NULL,
  version      VARCHAR  NOT NULL,
  duty         VARCHAR  NOT NULL DEFAULT 'master',
  db_user      VARCHAR  NOT NULL,
  is_online    BOOLEAN  NOT NULL DEFAULT TRUE,
  pgdata       VARCHAR  NOT NULL,
  master_host  VARCHAR  NULL,
  master_port  INT      NULL,
  UNIQUE (db_host, instance)
);

GRANT ALL ON util_instance TO util_exec;
GRANT ALL ON util_instance_instance_id_seq TO util_exec;

--------------------------------------------------------------------------------
-- CREATE FUNCTIONS
--------------------------------------------------------------------------------

/**
* Register instance information or changes
*
* When remote systems call this function to register instances, we want to
* do two things:
*
* - Deflect duplicate inserts.
* - Catch relevant changes
*
* In effect, we'll track new instances the first time they're encountered.
* Subsequent modifications will only be made if one of these items changes:
*
* - duty : Changing the server between master and slave is important.
* - is_online : Attempt to always know the current state of all instances.
* - master_host : Track upstream replication changes where applicable.
* - master_port : The port is relevant to the above as well.
*/
CREATE OR REPLACE FUNCTION sp_instance_checkin(
  sHost VARCHAR, sInstance VARCHAR, nPort INT, sVer VARCHAR,
  sDuty VARCHAR, sUser VARCHAR, bOnline BOOLEAN, sDataDir VARCHAR,
  sMasterHost VARCHAR, nMasterPort INT
)
RETURNS VOID
AS $$
DECLARE
  rInst utility.util_instance%ROWTYPE;
BEGIN
  SELECT INTO rInst *
    FROM utility.util_instance
   WHERE db_host = sHost
     AND instance = sInstance;

  -- If the above query does not locate this instance, dump all of the fields
  -- into the tracking table unchanged. Subsequent registration calls will
  -- fall through to the next section.

  IF NOT FOUND THEN
    INSERT INTO utility.util_instance (
        db_host, instance, db_port, version, duty, db_user, is_online, pgdata,
        master_host, master_port
    ) VALUES (
        sHost, sInstance, nPort, sVer, sDuty, sUser, bOnline, sDataDir,
        sMasterHost, nMasterPort
    );

    RETURN;
  END IF;

  -- Of the mentioned relevant fields in our header, only update when those
  -- elements change. Normally we'd ignore the pgdata entry, but until our
  -- systems adhere to the recommended SOP, many of these could change.

  IF (sDuty, bOnline, sMasterHost, nMasterPort, sVer, sDataDir)
       IS DISTINCT FROM
     (rInst.duty, rInst.is_online, rInst.master_host, rInst.master_port,
      rInst.version, rInst.pgdata)
  THEN
    UPDATE utility.util_instance
       SET duty = sDuty,
           is_online = bOnline,
           master_host = sMasterHost,
           master_port = nMasterPort,
           version = sVer,
           pgdata = COALESCE(pgdata, sDataDir)
     WHERE db_host = sHost
       AND instance = sInstance;
  END IF;

  RETURN;

END;
$$ LANGUAGE plpgsql;

REVOKE EXECUTE ON FUNCTION sp_instance_checkin(
  VARCHAR, VARCHAR, INT, VARCHAR, VARCHAR,
  VARCHAR, BOOLEAN, VARCHAR, VARCHAR, INT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION sp_instance_checkin(
  VARCHAR, VARCHAR, INT, VARCHAR, VARCHAR,
  VARCHAR, BOOLEAN, VARCHAR, VARCHAR, INT
) TO util_exec;
