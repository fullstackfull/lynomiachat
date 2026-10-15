// THE MARKETING SITE'S OWN TAILWIND CONFIG.
//
// WHY A SECOND CONFIG. The marketing stylesheet was 1.5 MB. It is generated from the SAME
// `tailwind.config.js` the dashboard uses, whose `content` globs reach every Vue file in
// `app/javascript/dashboard/**` -- so a page that is twenty ERB partials and no JavaScript was shipping
// every utility the agent console has ever needed, and, through `iconsPlugin`, rules for the seven icon
// collections it loads. The site uses four icons.
//
// Reached from `app/javascript/marketing/application.scss` with Tailwind's `@config` directive, which
// applies to that stylesheet alone. Nothing else in the build sees this file, and `tailwind.config.js` is
// untouched -- the dashboard, the widget, the portal and Super Admin all still compile exactly as before.
//
// THE THEME IS THE SHARED ONE, imported rather than restated: the `lyn` ramp, the type scale, the spacing
// ladder and the keyframes must not fork, or the marketing site and the dashboard would drift apart in the
// one place this redesign exists to bring together. Only `content` and the icon collections narrow.
const shared = require('./tailwind.config.js');

module.exports = {
  ...shared,
  content: [
    './custom/app/views/marketing/**/*.erb',
    './custom/app/views/layouts/marketing.html.erb',
    './app/javascript/marketing/**/*.{js,scss}',
  ],
  // `safelist` on the shared config names icons written into the DATABASE by the documentation seeder.
  // None of them reaches a marketing page, and a safelisted class is emitted whether or not it is used.
  safelist: [],
};
