import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import fs from 'fs';

// Single source of truth for the project version — bin/* and shell rcfiles
// read the same file at runtime; the docs site reads it at build time.
const version = fs.readFileSync('../version.txt', 'utf8').trim();

// Fork-friendly: GitHub Actions auto-sets these from repo context;
// local dev uses the defaults. See website/README.md if you fork.
const GITHUB_ORG = process.env.GITHUB_ORG || 'terchris';
const GITHUB_REPO = process.env.GITHUB_REPO || 'noclickops';

const config: Config = {
  title: 'noClickOps',
  tagline: 'No clicking around the portal. Just type the command.',
  favicon: 'img/favicon.svg',

  future: {
    v4: true,
  },

  url: 'https://noclickops.sovereignsky.no',
  baseUrl: '/',

  organizationName: GITHUB_ORG,
  projectName: GITHUB_REPO,

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    mermaid: true,
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: `https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/tree/main/website/`,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themes: [
    '@docusaurus/theme-mermaid',
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        language: ['en'],
        highlightSearchTermsOnTargetPage: true,
        explicitSearchResultPath: true,
        docsRouteBasePath: '/docs',
        indexBlog: false,
      },
    ],
  ],

  themeConfig: {
    // Open Graph / Twitter card image — used when the site URL is shared
    // on social platforms (Slack, LinkedIn, Twitter/X, Discord, etc.).
    // 1200x630 PNG generated from static/img/social-card.svg.
    image: 'img/social-card.png',
    colorMode: {
      defaultMode: 'light',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'noClickOps',
      logo: {
        alt: 'noClickOps logo',
        src: 'img/favicon.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          type: 'html',
          position: 'right',
          value: `<span class="badge badge--secondary">v${version}</span>`,
        },
        {
          href: `https://github.com/${GITHUB_ORG}/${GITHUB_REPO}`,
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Documentation',
          items: [
            {
              label: 'Docs',
              to: '/docs/',
            },
            {
              label: 'AI Developer Workflow',
              to: '/docs/ai-developer/',
            },
          ],
        },
        {
          title: 'Project',
          items: [
            {
              label: 'GitHub',
              href: `https://github.com/${GITHUB_ORG}/${GITHUB_REPO}`,
            },
            {
              label: 'Issues',
              href: `https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/issues`,
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} noClickOps contributors. MIT.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'powershell', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
