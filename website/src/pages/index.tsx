import React from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';

export default function Home(): React.JSX.Element {
  return (
    <Layout title="noclickops" description="Portable script suite for developers — type a command instead of clicking a UI.">
      <main style={{padding: '4rem 2rem', textAlign: 'center'}}>
        <h1>noclickops</h1>
        <p>Site under construction. The marketing homepage lands in PLAN-105.</p>
        <p>
          Documentation is live at <Link to="/docs/">/docs/</Link>.
        </p>
      </main>
    </Layout>
  );
}
