\echo '[mediask] seed auth and permissions'
\ir 99-seed-01-auth.sql

\echo '[mediask] seed hospital org and staff'
\ir 99-seed-02-org.sql

\echo '[mediask] seed outpatient and encounter fixtures'
\ir 99-seed-04-outpatient.sql

\echo '[mediask] seed emr and prescription fixtures'
\ir 99-seed-05-medical.sql
