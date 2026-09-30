#!/bin/bash
# API-level security checks against the E2E server (after e2e.js). Prints PASS/FAIL lines.
E=$(cd "$(dirname "$0")" && pwd); W=${WOO_DIR:-$E/woocommerce}; B=http://localhost:3100
read CK1 CS1 < $W/key.txt
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "PASS  $1 ($3)"; pass=$((pass+1)); else echo "FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi; }
login() { curl -s -D - -o /dev/null -H 'Content-Type: application/json' -d "{\"email\":\"$1\",\"password\":\"Password1!x\"}" $B/auth/sign_in \
  | tr -d '\r' | awk -F': ' 'tolower($1)=="access-token"{t=$2} tolower($1)=="client"{c=$2} tolower($1)=="uid"{u=$2} END{printf "-H access-token:%s -H client:%s -H uid:%s", t, c, u}'; }
code() { curl -s -o /tmp/api_body.json -w '%{http_code}' $1 "${@:2}"; }
ADMIN_A=$(login admin_a@commerce.lynomia.local); AGENT_A=$(login agent_a@commerce.lynomia.local)
OUTSIDER=$(login outsider_a@commerce.lynomia.local); ADMIN_B=$(login admin_b@commerce.lynomia.local)
A1=$(curl -s $ADMIN_A $B/api/v1/accounts/1/commerce/stores | python3 -c "import json,sys; print([s['id'] for s in json.load(sys.stdin)['payload'] if s['name']=='Syria Cosmetics'][0])")
B1=$(curl -s $ADMIN_B $B/api/v1/accounts/2/commerce/stores | python3 -c "import json,sys; print(json.load(sys.stdin)['payload'][0]['id'])")
echo "A1=$A1 B1=$B1"

ok 'admin A lists stores' 200 $(code "$ADMIN_A" $B/api/v1/accounts/1/commerce/stores)
if grep -q -e "$CK1" -e "$CS1" -e credentials /tmp/api_body.json; then ok 'store list has no credentials' clean leaked; else ok 'store list has no credentials' clean clean; fi
ok 'agent cannot list/manage stores' 401 $(code "$AGENT_A" $B/api/v1/accounts/1/commerce/stores)
ok 'agent cannot disconnect a store' 401 $(code "$AGENT_A" -X DELETE $B/api/v1/accounts/1/commerce/stores/$A1)
ok 'agent cannot rotate keys' 401 $(code "$AGENT_A" -X PATCH -H 'Content-Type: application/json' -d '{"status":"disabled"}' $B/api/v1/accounts/1/commerce/stores/$A1)
ok 'agent with inbox access reads the panel' 200 $(code "$AGENT_A" $B/api/v1/accounts/1/conversations/2/commerce/stores/$A1)
ok 'agent without inbox access is refused' 401 $(code "$OUTSIDER" $B/api/v1/accounts/1/conversations/2/commerce/stores/$A1)
ok 'admin B cannot enter account A' 401 $(code "$ADMIN_B" $B/api/v1/accounts/1/commerce/stores)
ok 'admin B cannot read A1 through its own conversation' 404 $(code "$ADMIN_B" $B/api/v1/accounts/2/conversations/1/commerce/stores/$A1)
ok 'admin A cannot read B1' 404 $(code "$ADMIN_A" $B/api/v1/accounts/1/conversations/2/commerce/stores/$B1)
ok 'admin A cannot modify B1' 404 $(code "$ADMIN_A" -X PATCH -H 'Content-Type: application/json' -d '{"status":"disabled"}' $B/api/v1/accounts/1/commerce/stores/$B1)
ok 'forged link token refused' 422 $(code "$AGENT_A" -X POST -H 'Content-Type: application/json' -d '{"token":"forged"}' $B/api/v1/accounts/1/conversations/7/commerce/stores/$A1/link)
ok 'name search refused' 422 $(code "$AGENT_A" -G --data-urlencode 'query=Layla Haddad' $B/api/v1/accounts/1/conversations/7/commerce/stores/$A1/customers)
ok 'SSRF: metadata IP refused at connect' 422 $(code "$ADMIN_A" -X POST -H 'Content-Type: application/json' -d "{\"provider\":\"woocommerce\",\"base_url\":\"https://169.254.169.254\",\"consumer_key\":\"$CK1\",\"consumer_secret\":\"$CS1\"}" $B/api/v1/accounts/1/commerce/stores)
cat /tmp/api_body.json; echo
ok 'SSRF: IPv6 loopback refused at connect' 422 $(code "$ADMIN_A" -X POST -H 'Content-Type: application/json' -d "{\"provider\":\"woocommerce\",\"base_url\":\"https://[::1]\",\"consumer_key\":\"$CK1\",\"consumer_secret\":\"$CS1\"}" $B/api/v1/accounts/1/commerce/stores)
ok 'malformed consumer key refused' 422 $(code "$ADMIN_A" -X POST -H 'Content-Type: application/json' -d '{"provider":"woocommerce","base_url":"https://shop.example.com","consumer_key":"ck_x","consumer_secret":"cs_y"}' $B/api/v1/accounts/1/commerce/stores)
ok 'unsupported provider refused' 422 $(code "$ADMIN_A" -X POST -H 'Content-Type: application/json' -d "{\"provider\":\"salla\",\"base_url\":\"https://shop.example.com\",\"consumer_key\":\"$CK1\",\"consumer_secret\":\"$CS1\"}" $B/api/v1/accounts/1/commerce/stores)
echo "api checks: $pass passed, $fail failed"
