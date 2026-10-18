/**
 * The Mac's three ways a thing gives under the hand, as Tailwind classes, so a button anywhere in the
 * island presses as its Swift twin does. Each spring is the nearest CSS curve from the spec's table.
 */

/**
 * `PressableStyle`: scale 0.94 on spring(0.2, 0.6), no fill, no hover, the pointing hand. For anything
 * clickable that is not a labelled pill, such as the chevrons of a queue or the header's back tab.
 */
export const PRESSABLE =
  'cursor-pointer select-none transition-transform duration-[220ms] ease-press active:scale-[0.94] disabled:cursor-default disabled:active:scale-100';

/**
 * `NotchPressStyle`: a white 9% wash in the same shape under the pointer, opacity 0.8 pressed, 0.4
 * disabled; with `lifts`, scale 1.022 hovered and 0.965 pressed. The wash is a pseudo element, so the
 * element needs `relative` and its own radius, which `rounded-[inherit]` passes to the wash.
 */
export function notchPress(lifts = true): string {
  const lift = lifts ? 'enabled:hover:scale-[1.022] enabled:active:scale-[0.965]' : '';
  return [
    'relative cursor-pointer select-none',
    'transition-[scale,opacity] duration-[340ms] ease-notch-hover',
    "after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:bg-white/[0.09] after:opacity-0 after:transition-opacity after:duration-[340ms] after:content-['']",
    'enabled:hover:after:opacity-100 enabled:active:opacity-80',
    'disabled:cursor-default disabled:opacity-40',
    lift,
  ].join(' ');
}

/** The answers on a card dim together while one is being signed, so a second press is not invited. */
export const ANSWERING_ROW = 'pointer-events-none opacity-[0.55]';
