# Roachize

## Usage

```
$ pg_dump -h postgreshost -f mydb.sql mydb
$ perl roachize.pl --source mydb.sql --dest mydb_for_cockroach.sql
$ psql -h localhost -U root -p 26257
root=> create database mydb;
\q
$ psql -h localhost -U root -p 26257 -d mydb < mydb_for_cockroach.sql
```

This is a HACK script to take a SQL (default) format output of pg_dump and emit
a modified version that can be run against a cockroachdb instance. It is probably
dependent on the versions of postgres I'm using and cockroach - 9.6 and 1.1.3

It depends on the structure of the SQL output from the pg_dump comand so isn't going
to work on a random sql file of postgres commands.

Usage:
  `perl perl roachize.pl --source mydb.sql --dest mydb_for_cockroach.sql [--2] [--omitdata]`

You can skip the `COPY` sections during debugging to speed up imports using `--omitdata`
You can indicate you are targeting a V2 alpha cluster with `--2`


What it does:

Processes the entire file looking for the primary key definitions to hoist into
the `CREATE TABLE` expressions- pg_dump creates the tables and adds the primary
key constraints later. Cockroachdb requires the primary key to be defined at
table creation. It also notices the creation of foreign key constraints and
remembers them to explicitly create indexes for them. Postgres auto-creates them
but cockroach does not and fails creating the constraints if the indexes do not
exist. It dumps the DDL for them as a block when it finds an explicit `CREATE
INDEX` which means this is after all tables have been created in a pg_dump

It then rewinds and starts processing the the file again, emitting the altered
`CREATE TABLE` commands and changing any primary keys that are integers into `SERIAL`.

It comments out:

```
  CREATE SEQUENCE
  ALTER TABLE ... PRIMARY KEY statemnts as they are already defined
  GRANT
  REVOKE
  COMMENT ON
  ALTER SEQUENCE
  SET
  CREATE EXTENSION
  ALTER TABLE \S+ OWNER
  ALTER TABLE.*nextval
  SELECT pg_catalog
```
It removes the following unsupported expressions:
```
  USING btree
   DEFERRABLE INITIALLY DEFERRED
   ON DELETE SET NULL;
```

