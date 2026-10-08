require 'rails_helper'
require 'json_refs'

RSpec.describe 'OpenAPI document', type: :request do
  let(:swagger_root) { Rails.root.join('swagger') }
  let(:committed) { JSON.parse(swagger_root.join('swagger.json').read) }

  it 'is valid against the OpenAPI 3.1.0 meta-schema' do
    expect(skooma_openapi_schema).to be_valid_document
  end

  # CI's own sync gate (.circleci/config.yml) re-runs `rake swagger:build` and git-diffs swagger.json. It does
  # not run on this fork, and it never looks at the four tag_groups/*_swagger.json files that the same task
  # regenerates, so both can go stale against the YAML sources unnoticed.
  it 'is in sync with the YAML sources it is built from' do
    built = Dir.chdir(swagger_root) do
      JsonRefs.call(YAML.safe_load(File.read('index.yml')), resolve_local_ref: false, resolve_file_ref: true)
    end
    expect(committed).to eq(JSON.parse(JSON.generate(built)))
  end

  it 'has per-group split files that agree with it' do
    operations = lambda do |spec, tags|
      spec['paths'].flat_map do |path, item|
        item.filter_map do |method, operation|
          next unless operation.is_a?(Hash) && operation['tags'].is_a?(Array)
          next unless tags.nil? || operation['tags'].intersect?(tags)

          "#{method.upcase} #{path}"
        end
      end.sort
    end

    committed['x-tagGroups'].each do |group|
      name = group['name'].casecmp('others').zero? ? 'other' : group['name'].downcase.tr(' ', '_')
      split = JSON.parse(swagger_root.join('tag_groups', "#{name}_swagger.json").read)

      expect(split['info']).to eq(committed['info'])
      expect(operations.call(split, nil)).to eq(operations.call(committed, group['tags']))
    end
  end
end
