import React from 'react';
import CodeBlock from '@theme/CodeBlock';
import styles from './styles.module.css';

export default function QuickInstall(): React.JSX.Element {
  return (
    <section className={styles.quickInstall}>
      <div className="container">
        <h2 className="text--center">Install</h2>
        <p className="text--center">
          One line, one time, per developer machine:
        </p>
        <div className={styles.codeBlockWrap}>
          <CodeBlock language="bash">
            {`curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash`}
          </CodeBlock>
        </div>
        <p className={`text--center ${styles.hint}`}>
          Windows: run via Git Bash or WSL (a native PowerShell installer exists but is
          unverified — see the <a href="/docs/">README</a>).
        </p>
      </div>
    </section>
  );
}
