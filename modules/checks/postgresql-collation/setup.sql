-- Databases in each state the probe distinguishes, under the en_US.UTF-8
-- collation magnetite's databases use: one as created, so recorded and
-- actual agree; two drifted, their recorded version forged to 1.0, one of
-- them parked; one whose name needs escaping in a label value; and one with
-- no recorded version, as template0 has on magnetite.
CREATE ROLE probe LOGIN;
CREATE DATABASE matching TEMPLATE template0 LOCALE 'en_US.UTF-8';
CREATE DATABASE drifted TEMPLATE template0 LOCALE 'en_US.UTF-8';
CREATE DATABASE parked TEMPLATE template0 LOCALE 'en_US.UTF-8';
CREATE DATABASE "odd""name\x" TEMPLATE template0 LOCALE 'en_US.UTF-8';
CREATE DATABASE unrecorded TEMPLATE template0 LOCALE 'en_US.UTF-8';
UPDATE pg_database SET datcollversion = '1.0' WHERE datname IN ('drifted', 'parked', 'odd"name\x');
UPDATE pg_database SET datcollversion = NULL WHERE datname = 'unrecorded';
