// Validates the connector's GraphQL documents against Shopify's published Admin API schema (introspection JSON).
const fs = require('fs');
const zlib = require('zlib');
const { buildClientSchema, parse, validate, visit, TypeInfo, visitWithTypeInfo, getNamedType } = require('graphql');

const [schemaPath, documentsPath] = process.argv.slice(2);
const raw = JSON.parse(zlib.gunzipSync(fs.readFileSync(schemaPath)));
const schema = buildClientSchema(raw.data || raw);
const documents = JSON.parse(fs.readFileSync(documentsPath, 'utf8'));
let failures = 0;
for (const [name, source] of Object.entries(documents)) {
  const ast = parse(source);
  const errors = validate(schema, ast);
  const deprecated = [];
  const typeInfo = new TypeInfo(schema);
  visit(ast, visitWithTypeInfo(typeInfo, {
    Field() {
      const field = typeInfo.getFieldDef();
      if (field?.deprecationReason) deprecated.push(`${typeInfo.getParentType()}.${field.name}`);
    },
  }));
  const operations = ast.definitions.map(d => d.operation);
  const ok = errors.length === 0 && deprecated.length === 0 && operations.every(o => o === 'query');
  if (!ok) failures += 1;
  console.log(`${ok ? 'VALID' : 'INVALID'}  ${name}  operation=${operations.join(',')}  errors=${errors.length}  deprecated=${deprecated.join(',') || 'none'}`);
  errors.forEach(e => console.log(`   ${e.message}`));
}
console.log(`${Object.keys(documents).length - failures}/${Object.keys(documents).length} documents valid against ${schemaPath.split('/').pop()}`);
process.exit(failures ? 1 : 0);
