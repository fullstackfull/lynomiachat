#!/bin/bash
# Phase 6 credential-leak scan: every known test secret and every simulator-issued token, searched in plaintext in the
# E2E and rehearsal databases, their Redis databases, every server/job/E2E log and result, and the final image.
# Prints labels and counts only, never a value.
S=$SCRATCH
R=/home/user/lynomiachat
O=$S/p6/leak; rm -rf $O; mkdir -p $O/targets
export PGPASSWORD=postgres

# ---- secrets (label<TAB>value), kept in the scratchpad only
: > $O/secrets.tsv; chmod 600 $O/secrets.tsv
for name in SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT \
            E2E_SALLA_WEBHOOK_SECRET E2E_SALLA_CLIENT_SECRET E2E_ZID_CLIENT_SECRET E2E_SHOPIFY_CLIENT_SECRET; do
  printf 'e2e:%s\t%s\n' $name "$(grep "^$name=" $S/commerce/e2e/e2e.env | cut -d= -f2-)" >> $O/secrets.tsv
done
for name in SECRET_KEY_BASE; do printf 'rehearsal:%s\t%s\n' $name "$(grep "^$name=" $S/p6/rehearsal/staging.env | cut -d= -f2-)" >> $O/secrets.tsv; done
while IFS='=' read -r name value; do printf 'rehearsal:%s\t%s\n' $name "$value" >> $O/secrets.tsv; done < $S/p6/rehearsal/encryption.env
while IFS='=' read -r name value; do printf 'rehearsal:%s\t%s\n' $name "$value" >> $O/secrets.tsv; done < $S/p6/rehearsal/ui.env
for f in key key2 key3 subkey; do
  read -r ck cs < $S/commerce/woo/$f.txt
  printf 'woo:%s.consumer_key\t%s\nwoo:%s.consumer_secret\t%s\n' $f "$ck" $f "$cs" >> $O/secrets.tsv
done
# Tokens the simulated providers issue (docs/commerce/e2e/*/): access, refresh, manager and authorization tokens, codes.
TOKENS='e2e-access-m[0-9]|e2e-refresh-m[0-9]|e2e-zid-(manager|auth|refresh|code)-[0-9]|e2e-shp-(access|refresh)-[0-9]|e2e-shopify-code-[a-z0-9]'

# ---- targets
pg_dump -h localhost -U postgres --exclude-table-data=installation_configs lyn_commerce_e2e > $O/targets/db_e2e.sql
pg_dump -h localhost -U postgres --exclude-table-data=installation_configs lyn_p6_staging > $O/targets/db_rehearsal.sql
psql -h localhost -U postgres -tAc "select name, serialized_value from installation_configs" lyn_commerce_e2e > $O/installation_configs_e2e.txt
cat > $O/redis_dump.rb <<'RUBY'
require 'redis'
r = Redis.new(url: ARGV[0])
File.open(ARGV[1], 'w') do |f|
  r.scan_each(count: 1000) do |k|
    next if k.start_with?('E2E::')   # the simulated providers' own state (their side of the contract)
    v = case r.type(k)
        when 'string' then r.get(k)
        when 'hash' then r.hgetall(k).to_a.flatten.join("\n")
        when 'list' then r.lrange(k, 0, -1).join("\n")
        when 'set' then r.smembers(k).join("\n")
        when 'zset' then r.zrange(k, 0, -1).join("\n")
        else ''
        end
    f.puts(k, v)
  end
end
RUBY
for db in 12 13; do
  docker run --rm --network host -v $O:/o lynomia/verify:base bash -lc "cd /app && bundle exec ruby /o/redis_dump.rb redis://localhost:6379/$db /o/targets/redis_$db.txt" 2>/dev/null
done
mkdir -p $O/targets/logs
cp $R/tmp/e2e_server.log $O/targets/logs/repo_tmp_e2e_server.log 2>/dev/null; cp $R/tmp/e2e_sim.log $O/targets/logs/repo_tmp_e2e_sim.log 2>/dev/null
for d in woo_p6 salla_p6 zid_p6 shopify_p6; do [ -d $S/p6/e2e/$d ] && cp -r $S/p6/e2e/$d $O/targets/logs/; done
cp $S/p6/rehearsal/*.log $S/p6/rehearsal/*.txt $O/targets/logs/ 2>/dev/null; cp -r $S/p6/rehearsal/ui $O/targets/logs/rehearsal_ui 2>/dev/null
cp -r $S/p6/rehearsal/harness/out $O/targets/logs/harness_out 2>/dev/null
for c in $(docker ps -a --format '{{.Names}}' | grep -E '^lyn6'); do docker logs $c > $O/targets/logs/container_$c.log 2>&1; done

# ---- scan
{
  printf '%-44s %s\n' TARGET 'SECRET-HITS  TOKEN-HITS'
  for tgt in $O/targets/db_e2e.sql $O/targets/db_rehearsal.sql $O/targets/redis_12.txt $O/targets/redis_13.txt $O/targets/logs; do
    hits=0
    while IFS=$'\t' read -r label value; do
      [ -z "$value" ] && continue
      n=$(grep -r -a -F -c -- "$value" $tgt 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
      [ "$n" -gt 0 ] && echo "  HIT $label in $(basename $tgt): $n" >&2
      hits=$((hits + n))
    done < $O/secrets.tsv
    th=$(grep -r -a -E -o -- "$TOKENS" $tgt 2>/dev/null | wc -l)
    printf '%-44s %-12s %s\n' "$(basename $tgt)" $hits $th
  done
  echo "image $(docker images --format '{{.Repository}}:{{.Tag}}' | grep final-): $(docker run --rm lynomia/staging:final-f842e12e bash -lc 'cat > /tmp/s; cut -f2 /tmp/s | grep -v "^$" > /tmp/v; grep -r -a -F -l -f /tmp/v /app 2>/dev/null | wc -l' < $O/secrets.tsv) files containing a test secret"
  echo "installation_configs (designated store for app secrets, write-only in Super Admin): $(grep -c -F -f <(cut -f2 $O/secrets.tsv | grep -v '^$') $O/installation_configs_e2e.txt) rows hold a test secret: $(grep -F -f <(cut -f2 $O/secrets.tsv | grep -v '^$') $O/installation_configs_e2e.txt | cut -d'|' -f1 | tr '\n' ' ')"
} 2>&1 | tee $O/result.txt
