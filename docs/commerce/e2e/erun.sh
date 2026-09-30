#!/bin/bash
# Runs a command in the Ruby 3.4.4 / Node 24 image against this checkout with the E2E production environment.
E=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$E/../../.." && pwd)
exec docker run --rm --network host --env-file $E/e2e.env -v $ROOT:/app -v lyn_nm:/app/node_modules -w /app lynomia/verify:base bash -lc "$*"
