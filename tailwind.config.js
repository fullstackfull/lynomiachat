const { slateDark } = require('@radix-ui/colors');
import { colors } from './theme/colors';
import { icons } from './theme/icons';
const defaultTheme = require('tailwindcss/defaultTheme');
const {
  iconsPlugin,
  getIconCollections,
} = require('@egoist/tailwindcss-icons');

const defaultSansFonts = [
  '-apple-system',
  'system-ui',
  'BlinkMacSystemFont',
  '"Segoe UI"',
  'Roboto',
  '"Helvetica Neue"',
  'Tahoma',
  'Arial',
  'sans-serif !important',
];

const tailwindConfig = {
  darkMode: 'class',
  content: [
    './app/javascript/superadmin_pages/**/*.vue',
    './app/javascript/widget/**/*.vue',
    './app/javascript/v3/**/*.vue',
    './app/javascript/dashboard/**/*.vue',
    './app/javascript/portal/**/*.vue',
    './app/javascript/shared/**/*.vue',
    './app/javascript/survey/**/*.vue',
    './app/javascript/dashboard/components-next/**/*.vue',
    './app/javascript/dashboard/helper/**/*.js',
    './app/javascript/dashboard/composables/**/*.js',
    './app/javascript/dashboard/components-next/**/*.js',
    './app/javascript/dashboard/routes/dashboard/**/**/*.js',
    './app/javascript/super_admin/**/*.vue',
    './app/views/**/*.erb',
    './custom/app/views/**/*.erb',
  ],
  // Documentation category icons come out of the DATABASE -- `categories.icon`, written by
  // Documentation::ContentSeeder#upsert_category from custom/db/documentation/manifest.yml -- so the class
  // name appears in no file the globs above scan, no rule is generated, and the eight render sites that call
  // `render_emoji_or_icon` emit an empty span. These are the only database-driven icon classes in the product.
  safelist: [
    'i-lucide-rocket',
    'i-lucide-messages-square',
    'i-lucide-users',
    'i-lucide-megaphone',
    'i-lucide-message-circle',
    'i-lucide-alert-triangle',
    'i-lucide-workflow',
    'i-lucide-shopping-bag',
    'i-lucide-building',
    'i-lucide-plug',
    'i-lucide-shield',
    'i-lucide-life-buoy',
    'i-lucide-sparkles',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: defaultSansFonts,
        inter: ['Inter', ...defaultSansFonts],
        interDisplay: ['InterDisplay', ...defaultSansFonts],
        // The marketing site's stack. Arabic resolves to IBM Plex Sans Arabic and everything else falls
        // through to Inter, because the Arabic @font-face rules carry a `unicode-range`
        // (app/javascript/marketing/fonts/plex-arabic.scss). One class, both locales, no branch in any
        // template -- and an English page downloads no Arabic file.
        lyn: ['"IBM Plex Sans Arabic"', 'Inter', ...defaultSansFonts],
      },
      fontWeight: {
        420: '420',
        440: '440',
        460: '460',
        520: '520',
        620: '620',
      },
      // The product had colour, type, breakpoints, icons and motion, but no scale for the dimensions
      // below — which is why 14 modal widths, 16 one-off radii, 46 bespoke shadows and a z-index ladder
      // running to 99999 grew in their place. These are additive: nothing changes appearance until a
      // call site moves onto them.
      spacing: {
        // The settings/page header height, written as `h-[3.25rem]` in eight files.
        13: '3.25rem',
      },
      borderRadius: {
        // sm/md/lg/xl are Tailwind's own 4/6/8/12px and are already the de-facto steps; naming the
        // roles here so a reviewer can tell a deliberate step from an arbitrary value.
        control: '0.375rem', // 6px  — inputs, selects, badges, menu items
        surface: '0.5rem', //   8px  — buttons, cards, dropdown bodies
        overlay: '0.75rem', //  12px — dialogs, drawers, popovers
      },
      boxShadow: {
        raised: 'var(--shadow-raised)',
        overlay: 'var(--shadow-overlay)',
        modal: 'var(--shadow-modal)',
      },
      blur: {
        // `backdrop-blur-[100px]` appears 45 times in 41 files as an unnamed token.
        panel: '100px',
      },
      height: {
        // One control ladder shared by buttons, inputs, selects, chips and badges, so a filter bar
        // lines up with the button beside it. 40px is also the mobile tap-target floor.
        'control-xs': '1.5rem',
        'control-sm': '2rem',
        'control-md': '2.25rem',
        'control-lg': '2.5rem',
      },
      minHeight: {
        'control-xs': '1.5rem',
        'control-sm': '2rem',
        'control-md': '2.25rem',
        'control-lg': '2.5rem',
      },
      zIndex: {
        sticky: '10',
        dropdown: '50',
        drawer: '60',
        modal: '70',
        toast: '80',
      },
      typography: {
        bubble: {
          css: {
            color: 'rgb(var(--slate-12))',
            lineHeight: '1.6',
            fontSize: '14px',
            '*': {
              '&:first-child': {
                marginTop: '0',
              },
            },
            overflowWrap: 'anywhere',

            strong: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
            },

            b: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
            },

            h1: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1.25rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            h2: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            h3: {
              color: 'rgb(var(--slate-12))',
              fontWeight: '700',
              fontSize: '1rem',
              '&:first-child': {
                marginTop: '0',
              },
            },
            hr: {
              marginTop: '1.5em',
              marginBottom: '1.5em',
            },
            a: {
              color: 'rgb(var(--slate-12))',
              textDecoration: 'underline',
            },
            ul: {
              paddingInlineStart: '0',
              listStylePosition: 'inside',
            },
            ol: {
              paddingInlineStart: '0',
              listStylePosition: 'inside',
            },
            'ul > li': {
              marginBlockEnd: '0.5em',
              listStyleType: 'disc',
              paddingInlineStart: '1.5em',
              textIndent: '-1.5em',
            },
            'ol > li': {
              marginBlockEnd: '0.5em',
              listStyleType: 'decimal',
              paddingInlineStart: '1.5em',
              textIndent: '-1.5em',
            },
            'li > p:first-child': {
              display: 'inline',
            },
            'li > *': {
              textIndent: '0',
            },
            blockquote: {
              color: 'rgb(var(--slate-11))',
              borderLeft: `4px solid rgb(var(--black-alpha-1))`,
              paddingLeft: '1em',
              '[dir="rtl"] &': {
                borderLeft: 'none',
                paddingLeft: '0',
                borderRight: `4px solid rgb(var(--black-alpha-1))`,
                paddingRight: '1em',
              },
              '[dir="ltr"] &': {
                borderRight: 'none',
                paddingRight: '0',
              },
            },
            code: {
              backgroundColor: 'rgb(var(--alpha-3))',
              color: 'rgb(var(--slate-11))',
              padding: '0.2em 0.4em',
              borderRadius: '4px',
              fontSize: '0.95em',
              '&::before': {
                content: `none`,
              },
              '&::after': {
                content: `none`,
              },
            },
            pre: {
              backgroundColor: 'rgb(var(--alpha-3))',
              padding: '1em',
              borderRadius: '6px',
              overflowX: 'auto',
            },
            table: {
              width: '100%',
              borderCollapse: 'collapse',
            },
            th: {
              padding: '0.75em',
              color: 'rgb(var(--slate-12))',
              border: `none`,
              textAlign: 'start',
              fontWeight: '600',
            },
            tr: {
              border: `none`,
            },
            td: {
              padding: '0.75em',
              border: `none`,
            },
            img: {
              maxWidth: '100%',
              height: 'auto',
              marginTop: 'unset',
              marginBottom: 'unset',
            },
          },
        },
      },
    },
    screens: {
      xs: '480px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
      '3xl': '1900px',
    },
    fontSize: {
      ...defaultTheme.fontSize,
      xxxs: '0.5rem',
      xxs: '0.625rem',
    },
    colors: {
      transparent: 'transparent',
      white: '#fff',
      'modal-backdrop-light': 'rgba(0, 0, 0, 0.4)',
      'modal-backdrop-dark': 'rgba(0, 0, 0, 0.6)',
      current: 'currentColor',
      ...colors,
      body: slateDark.slate7,
    },
    keyframes: {
      ...defaultTheme.keyframes,
      wiggle: {
        '0%': { transform: 'translateX(0)' },
        '15%': { transform: 'translateX(0.375rem)' },
        '30%': { transform: 'translateX(-0.375rem)' },
        '45%': { transform: 'translateX(0.375rem)' },
        '60%': { transform: 'translateX(-0.375rem)' },
        '75%': { transform: 'translateX(0.375rem)' },
        '90%': { transform: 'translateX(-0.375rem)' },
        '100%': { transform: 'translateX(0)' },
      },
      'fade-in-up': {
        '0%': { opacity: 0, transform: 'translateY(0.5rem)' },
        '100%': { opacity: 1, transform: 'translateY(0)' },
      },
      'loader-pulse': {
        '0%': { opacity: 0.4 },
        '50%': { opacity: 1 },
        '100%': { opacity: 0.4 },
      },
      'card-select': {
        '0%, 100%': {
          transform: 'translateX(0)',
        },
        '50%': {
          transform: 'translateX(1px)',
        },
      },
      shake: {
        '0%, 100%': { transform: 'translateX(0)' },
        '25%': { transform: 'translateX(0.234375rem)' },
        '50%': { transform: 'translateX(-0.234375rem)' },
        '75%': { transform: 'translateX(0.234375rem)' },
      },
      // THE CHANNEL STRIP. The track holds the same row of marks TWICE and travels exactly -50% of its own
      // width, so the moment the first copy has left, the second is sitting precisely where the first
      // started and the loop restarts with nothing to see. A percentage is what makes that exact: a pixel
      // figure would have to be re-measured for every viewport, every font and both writing directions, and
      // would show a jump wherever it was out by a pixel.
      //
      // TWO DIRECTIONS, because this site is read in both. Under `dir="rtl"` the row must travel the way
      // Arabic reads -- rightwards -- or the strip scrolls backwards for the primary market.
      'marquee-ltr': {
        from: { transform: 'translateX(0)' },
        to: { transform: 'translateX(-50%)' },
      },
      'marquee-rtl': {
        from: { transform: 'translateX(0)' },
        to: { transform: 'translateX(50%)' },
      },
      // The hero's product screenshot settles in rather than appearing. One orchestrated moment on the
      // page, per the design rule, and it is the element the page is about.
      'rise-in': {
        from: { opacity: 0, transform: 'translateY(1.25rem) scale(0.985)' },
        to: { opacity: 1, transform: 'translateY(0) scale(1)' },
      },
      // The ring that leaves the hero's live dot. The dot itself does not move -- a second, absolutely
      // positioned span expands out of it and fades -- so nothing reflows and the text beside it is still.
      'live-ring': {
        '0%': { opacity: 0.55, transform: 'scale(1)' },
        '70%, 100%': { opacity: 0, transform: 'scale(2.6)' },
      },
    },
    animation: {
      ...defaultTheme.animation,
      wiggle: 'wiggle 0.5s ease-in-out',
      'fade-in-up': 'fade-in-up 0.3s ease-out',
      'loader-pulse': 'loader-pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      'card-select': 'card-select 0.25s ease-in-out',
      shake: 'shake 0.3s ease-in-out 0s 2',
      // 48s for a full pass of a ten-mark row doubled. Slow enough to read a logo rather than register a
      // blur, and `linear` because a marquee that eases is a marquee that visibly restarts.
      'marquee-ltr': 'marquee-ltr 48s linear infinite',
      'marquee-rtl': 'marquee-rtl 48s linear infinite',
      'rise-in': 'rise-in 0.7s cubic-bezier(0.16, 1, 0.3, 1) both',
      'live-ring': 'live-ring 2.2s cubic-bezier(0, 0, 0.2, 1) infinite',
    },
  },
  plugins: [
    // eslint-disable-next-line
    require('@tailwindcss/typography'),
    iconsPlugin({
      collections: {
        woot: { icons },
        ...getIconCollections([
          'lucide',
          'logos',
          'ri',
          'ph',
          'material-symbols',
          'teenyicons',
          'fluent',
        ]),
      },
    }),
  ],
};

module.exports = tailwindConfig;
