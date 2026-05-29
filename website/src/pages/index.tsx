import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import QuickInstall from '@site/src/components/QuickInstall';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  const githubUrl = `https://github.com/${siteConfig.organizationName}/${siteConfig.projectName}`;
  const faviconUrl = useBaseUrl('/img/favicon.svg');

  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className={clsx('container', styles.heroContainer)}>
        <img src={faviconUrl} alt="noclickops" className={styles.heroLogo} />
        <h1 className={clsx('hero__title', styles.heroTitle)}>{siteConfig.title}</h1>
        <p className={clsx('hero__subtitle', styles.heroSubtitle)}>{siteConfig.tagline}</p>
        <div className={styles.heroButtons}>
          <Link className="button button--lg button--primary" to="/docs/">
            Get Started
          </Link>
          <Link className="button button--lg button--outline" to="/docs/commands">
            Commands
          </Link>
          <Link className="button button--lg button--outline" href={githubUrl}>
            GitHub
          </Link>
        </div>
      </div>
    </header>
  );
}

export default function Home(): React.JSX.Element {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout title="Home" description={siteConfig.tagline}>
      <HomepageHeader />
      <main>
        <HomepageFeatures />
        <QuickInstall />
      </main>
    </Layout>
  );
}
