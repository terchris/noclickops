import React from 'react';
import Link from '@docusaurus/Link';
import styles from './styles.module.css';

export type CommandCategory = {
  id: string;
  label: string;
  description: string;
  count: number;
};

type Props = {
  category: CommandCategory;
};

// Anchor slug — must match Docusaurus's automatic heading-anchor slugger
// (github-slugger). For "Git / pull requests": lowercase → "git / pull requests";
// spaces → hyphens → "git-/-pull-requests"; drop non-alphanumeric (keep hyphens) →
// "git--pull-requests" (double dash, intentional). The double dash matches what
// Docusaurus emits for `## Git / pull requests`, so the card link resolves.
function anchorFor(label: string): string {
  return (
    '#' +
    label
      .toLowerCase()
      .replace(/ /g, '-')
      .replace(/[^a-z0-9-]/g, '')
  );
}

export default function CommandCategoryCard({category}: Props): React.JSX.Element {
  return (
    <Link to={`/docs/commands${anchorFor(category.label)}`} className={styles.card}>
      <h4 className={styles.title}>{category.label}</h4>
      <p className={styles.description}>{category.description}</p>
      <span className={styles.count}>
        {category.count} {category.count === 1 ? 'command' : 'commands'}
      </span>
    </Link>
  );
}
