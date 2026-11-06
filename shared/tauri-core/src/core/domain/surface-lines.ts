/** The movable drawing's own presses, as its toolbar names them. */
export const SurfaceLines = {
  fit: 'Fit the map',
  arrange: 'Arrange again',
  zoomOut: 'Zoom out',
  zoomIn: 'Zoom in',
  zoom: 'Zoom',
  size: 'Size',
  smaller: 'Smaller marks',
  larger: 'Larger marks',
  percent: (share: number) => `${Math.round(share * 100)}%`,
} as const;
