import React from 'react';
import CommandCategoryCard, {CommandCategory} from '../CommandCategoryCard';
import categoriesData from '@site/src/data/categories.json';
import styles from './styles.module.css';

export default function CommandCategoryGrid(): React.JSX.Element | null {
  const categories = categoriesData as CommandCategory[];
  const nonEmpty = categories.filter((c) => c.count > 0);
  if (nonEmpty.length === 0) return null;

  return (
    <div className={styles.grid}>
      {nonEmpty.map((category) => (
        <CommandCategoryCard key={category.id} category={category} />
      ))}
    </div>
  );
}
