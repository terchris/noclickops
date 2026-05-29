import React from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  emoji: string;
  description: React.ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'One command per task',
    emoji: '⌨️',
    description: (
      <>
        Install, scaffold, deploy, observe — without clicking through the Azure DevOps
        portal or the Azure portal.
      </>
    ),
  },
  {
    title: 'Works in any repo',
    emoji: '📁',
    description: (
      <>
        Derives the target's identity from <code>git remote get-url origin</code> at call
        time. The same commands work across every supported repo on your machine.
      </>
    ),
  },
  {
    title: 'Wraps existing pipelines',
    emoji: '🔌',
    description: (
      <>
        Triggers Azure DevOps pipelines and Azure CLI commands. Never re-implements them
        — new pipeline steps land for every user automatically.
      </>
    ),
  },
  {
    title: 'Multi-OS by default',
    emoji: '🖥️',
    description: (
      <>
        <code>.sh</code> for macOS / Linux / WSL / Git Bash. <code>.ps1</code> for native
        Windows. One <code>noclickops</code> on your PATH, every shell context.
      </>
    ),
  },
];

function Feature({title, emoji, description}: FeatureItem) {
  return (
    <div className={clsx('col col--6 col--lg-3')}>
      <div className={styles.feature}>
        <div className={styles.featureEmoji} aria-hidden="true">
          {emoji}
        </div>
        <Heading as="h3" className={styles.featureTitle}>
          {title}
        </Heading>
        <p className={styles.featureDescription}>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): React.JSX.Element {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
