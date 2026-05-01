\set ON_ERROR_STOP on

\echo '[mediask] bootstrap schemas and extensions'
\ir 00-bootstrap.sql

\echo '[mediask] drop existing dev tables'
\ir 00-drop-all.sql

\echo '[mediask] create base auth tables'
\ir 01-base-auth.sql

\echo '[mediask] create hospital org tables'
\ir 02-hospital-org.sql

\echo '[mediask] create appointment tables'
\ir 04-appointment.sql

\echo '[mediask] create java ai triage tables'
\ir 05-ai-triage.sql

\echo '[mediask] create medical tables'
\ir 06-medical.sql

\echo '[mediask] create audit tables'
\ir 07-domain-events.sql

\echo '[mediask] create rag tables'
\ir 20-rag-postgresql-ddl-v1.sql

\echo '[mediask] seed minimal dev data'
\ir 99-seed-data.sql
