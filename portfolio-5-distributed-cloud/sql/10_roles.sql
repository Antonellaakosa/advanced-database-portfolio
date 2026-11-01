-- Roles created when a node is first initialised. Passwords come in as psql variables, never typed here.
-- :role_set is 'primary' or 'shard'
SELECT :'role_set' = 'primary' AS is_primary \gset
\if :is_primary
  CREATE ROLE replicator REPLICATION LOGIN PASSWORD :'repl_pw';
  CREATE ROLE p5_app     LOGIN PASSWORD :'app_pw';
  CREATE ROLE p5_report  LOGIN PASSWORD :'report_pw';
  REVOKE CONNECT ON DATABASE upln FROM PUBLIC;
  GRANT  CONNECT ON DATABASE upln TO p5_app, p5_report;
\else
  CREATE ROLE fdw_user LOGIN PASSWORD :'fdw_pw';
  REVOKE CONNECT ON DATABASE shard FROM PUBLIC;
  GRANT  CONNECT ON DATABASE shard TO fdw_user;
\endif
