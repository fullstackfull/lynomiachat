// Lists the access Shopify's 2026-07 schema documents for every type and field the connector's documents touch.
const fs = require('fs');
const zlib = require('zlib');
const { buildClientSchema, parse, visit, TypeInfo, visitWithTypeInfo, getNamedType } = require('graphql');
const raw = JSON.parse(zlib.gunzipSync(fs.readFileSync(process.argv[2])));
const intro = raw.data || raw;
const byName = Object.fromEntries(intro.__schema.types.map(t => [t.name, t]));
const schema = buildClientSchema(intro);
const documents = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const access = new Map();
for (const source of Object.values(documents)) {
  const typeInfo = new TypeInfo(schema);
  visit(parse(source), visitWithTypeInfo(typeInfo, {
    Field() {
      const parent = typeInfo.getParentType()?.name;
      const field = byName[parent]?.fields?.find(f => f.name === typeInfo.getFieldDef()?.name);
      const type = getNamedType(typeInfo.getType())?.name;
      if (field?.requiredAccess) access.set(`${parent}.${field.name}`, field.requiredAccess);
      if (byName[type]?.requiredAccess) access.set(type, byName[type].requiredAccess);
    },
  }));
}
for (const [name, value] of [...access.entries()].sort()) console.log(`${name}: ${String(value).replace(/\s+/g, ' ').slice(0, 220)}`);
