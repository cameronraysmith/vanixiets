# The no-leak scan of vmTests.x86_64-linux.fleet-ingress, run inside the
# store container as one command per scan (declare-test-size-classes design
# D7). It reads every string and JSON column of every table of every
# database as `regulator`, counts the rows whose value holds any of the
# nonces given as arguments, and prints one JSON object:
#   {"hits": {"<db>.<table>.<column>": rows}, "columns": n, "tables": m}
# The queries are the ones helpers.py issued from the driver, two driver
# commands per column; here they stay on the container's loopback, four at
# a time, which the store answers independently of each other.
# Usage: python3 nonce_scan.py <netrc> <nonce>...
import base64
import concurrent.futures
import json
import netrc
import sys
import urllib.parse
import urllib.request

STORE = "http://127.0.0.1:4000/v1/sql"


def main():
    netrc_file, nonces = sys.argv[1], sys.argv[2:]
    login, _, password = netrc.netrc(netrc_file).authenticators("127.0.0.1")
    auth = base64.b64encode(f"{login}:{password}".encode()).decode()

    def gsql(sql, db):
        query = urllib.parse.urlencode({"sql": sql})
        request = urllib.request.Request(
            f"{STORE}?{query}",
            headers={"Authorization": f"Basic {auth}", "x-greptime-db-name": db},
        )
        with urllib.request.urlopen(request) as response:
            return json.load(response)["output"][0]["records"]["rows"]

    columns = gsql(
        "SELECT table_schema, table_name, column_name, lower(data_type) FROM information_schema.columns "
        "WHERE lower(data_type) IN ('string', 'json') AND table_schema NOT IN ('information_schema', 'greptime_private', 'pg_catalog')",
        "agent",
    )

    def count(entry):
        schema, table, column, kind = entry
        value = f'json_to_string("{column}")' if kind == "json" else f'"{column}"'
        held = " OR ".join(f"{value} LIKE '%{nonce}%'" for nonce in nonces)
        return f"{schema}.{table}.{column}", gsql(f'SELECT count(*) FROM "{schema}"."{table}" WHERE {held}', schema)[0][0]

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        hits = {name: rows for name, rows in pool.map(count, columns) if rows}
    tables = {(schema, table) for schema, table, _, _ in columns}
    json.dump({"hits": hits, "columns": len(columns), "tables": len(tables)}, sys.stdout)


main()
