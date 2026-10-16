/**
 * The one place the Super Admin documentation editor crosses between Markdown source and the installed
 * ProseMirror document model.
 *
 * `@chatwoot/prosemirror-schema` ships both halves of the pair the public renderer already consumes
 * (orchestrator ruling R3 point 1), so there is no second editor dependency and no second schema. Routing
 * every parse and serialize through this module is what lets one spec answer the R3 point 2 question --
 * does a parse-and-serialize of the corpus come back byte-identical -- for the whole editor at once.
 */
import {
  ArticleMarkdownTransformer,
  ArticleMarkdownSerializer,
  fullSchema,
} from '@chatwoot/prosemirror-schema';

export const parseMarkdown = source =>
  new ArticleMarkdownTransformer(fullSchema).parse(source);

export const serializeDoc = doc => ArticleMarkdownSerializer.serialize(doc);

export const roundTrip = source => serializeDoc(parseMarkdown(source));
