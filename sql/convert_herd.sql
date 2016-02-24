SET search_path to utility;

INSERT INTO ele_environment (env_name, env_descr)
SELECT DISTINCT environment, environment
  FROM util_instance
 WHERE environment IS NOT NULL;

ANALYZE ele_environment;

INSERT INTO ele_herd (environment_id, herd_name, db_port, vhost, pgdata)
SELECT DISTINCT ON (environment_id, instance, db_port, pgdata)
       e.environment_id, i.instance, i.db_port,
       coalesce(p.vhost, 'pg-' || 
           CASE WHEN i.instance ~ 'ion_arc' THEN 'exarc'
                WHEN i.instance ~ 't_arc' THEN 'baskets-arc'
                ELSE i.instance
            END
          || '-' ||
          CASE WHEN e.env_name = 'prod' THEN 'prd'
               ELSE e.env_name END
       ) AS vhost,
       pgdata
  FROM util_instance i
  JOIN ele_environment e ON (e.env_name = i.environment)
  LEFT JOIN util_drpair p ON (p.primary_id = i.instance_id)
 ORDER BY 1, 2, 3, 5, 4;

ANALYZE ele_herd;

INSERT INTO ele_server (hostname, environment_id)
SELECT DISTINCT i.db_host, e.environment_id
  FROM util_instance i
  JOIN ele_environment e ON (e.env_name = i.environment);

ANALYZE ele_server;

INSERT INTO ele_instance (
  version, local_pgdata, is_online, herd_id, server_id
)
SELECT coalesce(i.version, '') AS version, '' AS local_pgdata,
       i.is_online, h.herd_id, s.server_id
  FROM util_instance i
  JOIN ele_environment e ON (e.env_name = i.environment AND e.env_name = i.environment)
  JOIN ele_herd h ON (
           h.herd_name = i.instance AND
           h.db_port = i.db_port AND
           h.environment_id = e.environment_id
       )
  JOIN ele_server s ON (s.hostname = i.db_host AND s.environment_id = e.environment_id);

ANALYZE ele_instance;

WITH inst_map AS (
SELECT i.instance_id AS old_instance_id, ii.instance_id AS new_instance_id
  FROM util_instance i
  JOIN ele_environment e ON (e.env_name = i.environment AND e.env_name = i.environment)
  JOIN ele_herd h ON (
           h.herd_name = i.instance AND
           h.db_port = i.db_port AND
           h.environment_id = e.environment_id
       )
  JOIN ele_server s ON (s.hostname = i.db_host AND s.environment_id = e.environment_id)
  JOIN ele_instance ii ON (
         ii.herd_id = h.herd_id AND
         ii.server_id = s.server_id
       )
)
UPDATE ele_instance inst
   SET master_id = mm.new_instance_id
  FROM inst_map sm
  JOIN util_instance si ON (si.instance_id = sm.old_instance_id)
  JOIN inst_map mm ON (mm.old_instance_id = si.master_id)
 WHERE sm.new_instance_id = inst.instance_id;

VACUUM FULL ANALYZE ele_instance;
