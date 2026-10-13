import config from '../../../../config/markdown_embeds.yml';

// Every provider in the config is previewable: the two that were not -- github_gist (document.write) and wistia
// -- were removed because their templates emitted <script src> tags, which the public portal renders on this
// product's own origin (docs/documentation-v2/08-orchestrator-rulings.md R1.3).
export const embeds = Object.values(config).map(
  ({ regex, template, hide_source: hideSource }) => ({
    regex: new RegExp(regex),
    template,
    hideSource: Boolean(hideSource),
  })
);
