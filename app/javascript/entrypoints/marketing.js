// The marketing site's own entrypoint.
//
// It deliberately loads nothing but its stylesheet. The dashboard entrypoint pulls in Vue, the router, the
// store and a 15.9 MB icon chunk; a marketing page that imported any of that would blow the performance budget
// in docs/official-website/05-design-and-content-spec.md section 5 for no reader's benefit.
//
// The site needs no JavaScript to work: navigation is links, and the language switch is a link to the sibling
// URL rather than a script that rewrites the DOM -- which is the defect that flipped every Arabic visitor to
// English on the previous site.
import '../marketing/application.scss';
