/**
 * The Mac's measures that layout code reads as numbers rather than as classes, each the twin of a token in
 * styles.css and of a constant in DesignSystem.swift; test/design-tokens.test.ts holds the three together.
 */

/** `Memnox.Spacing`, the same steps as `--mx-space-*`. */
export const SPACING = { xxSmall: 2, xSmall: 4, small: 6, medium: 8, regular: 10, large: 12, xLarge: 16, xxLarge: 20 } as const;
