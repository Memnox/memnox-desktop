/**
 * The Mac's page measures that a page hands to an inline style or a grid template as numbers, in one plain module so
 * test/design-tokens.test.ts holds each to the Swift layout it comes from.
 */
export const PAGE_METRICS = {
  /** ProjectsLayout.searchWidth: the search beside Choose a folder, narrow enough that the count keeps its line. */
  projectSearch: 240,
  /** SkillSheetMetrics.versionWidth and instructionsHeight in the skill sheet. */
  skillVersion: 120,
  skillInstructions: 160,
  /** ActivityDestination's toolbar: the search and the kind, each no wider than this. */
  activitySearch: 280,
  activityKind: 150,
  /** McpServersLayout.searchWidth: the server search grows to this and no further. */
  hubSearch: 320,
  /** SkillsLayout.progressWidth: the import bar beside its count. */
  skillProgress: 120,
  /** HomeStart.Layout.trackMinimum: the two tracks sit side by side once each has this much room. */
  homeTrack: 280,
} as const;
