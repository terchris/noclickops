import React, {useEffect, useState} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import QuickInstall from '@site/src/components/QuickInstall';

import styles from './index.module.css';

// One full pass of the hero typing sequence takes ~11.2 s (4 commands).
// Hold the final state for a few seconds so the reader sees the result,
// then restart by bumping a key on the terminal block, which re-mounts it
// and re-triggers every CSS animation from scratch (cheap; CSS only).
const HERO_CYCLE_MS = 16000;

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  const logoUrl = useBaseUrl('/img/favicon.svg');
  const [cycle, setCycle] = useState(0);

  useEffect(() => {
    const id = window.setInterval(
      () => setCycle((c) => c + 1),
      HERO_CYCLE_MS,
    );
    return () => window.clearInterval(id);
  }, []);

  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className={clsx('container', styles.heroContainer)}>
        <div className={styles.heroIllustration}>
          <img src={logoUrl} alt="noClickOps logo" className={styles.heroMark} />
        </div>
        <div className={styles.heroContent}>
          <h1 className={clsx('hero__title', styles.heroTitle)}>{siteConfig.title}</h1>
          <p className={clsx('hero__subtitle', styles.heroSubtitle)}>
            No clicking around the portal.
            <br />
            <span className={styles.heroLead}>Just type the command.</span>
          </p>
          <div key={cycle} className={styles.heroTerminal} aria-label="Sample noClickOps workflow: add-service, deploy, info, logs">
            <div className={clsx(styles.heroLine, styles.heroLine1)}>
              <span className={styles.heroPrompt}>$</span> <span className={clsx(styles.heroTyping, styles.heroTyping1)}>noclickops add-service my-app</span>
            </div>
            <div className={clsx(styles.heroOutput, styles.heroOutput1)}>✓ Done. services/my-app on main.</div>
            <div className={clsx(styles.heroLine, styles.heroLine2)}>
              <span className={styles.heroPrompt}>$</span> <span className={clsx(styles.heroTyping, styles.heroTyping2)}>noclickops deploy my-app test</span>
            </div>
            <div className={clsx(styles.heroOutput, styles.heroOutput2)}>✓ Deploy complete. ca-my-app running.</div>
            <div className={clsx(styles.heroLine, styles.heroLine3)}>
              <span className={styles.heroPrompt}>$</span> <span className={clsx(styles.heroTyping, styles.heroTyping3)}>noclickops info my-app test</span>
            </div>
            <div className={clsx(styles.heroOutput, styles.heroOutput3)}>ca-my-app — Running (rev1, 1 replica)</div>
            <div className={clsx(styles.heroLine, styles.heroLine4)}>
              <span className={styles.heroPrompt}>$</span> <span className={clsx(styles.heroTyping, styles.heroTyping4)}>noclickops logs my-app test</span>
            </div>
          </div>
          <div className={styles.heroButtons}>
            <Link className="button button--lg button--primary" to="/docs/">
              Get Started
            </Link>
            <Link className="button button--lg button--outline" to="/docs/commands">
              Commands
            </Link>
          </div>
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
