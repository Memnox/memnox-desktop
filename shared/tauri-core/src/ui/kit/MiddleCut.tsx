import { useLayoutEffect, useRef, useState } from 'react';
import { middleCut } from '../../core';

/** One canvas measures every cut, since measuring text is all it is for. */
let measurer: CanvasRenderingContext2D | null | undefined;

function measure(font: string, text: string): number {
  if (measurer === undefined) measurer = document.createElement('canvas').getContext('2d');
  if (measurer === null) return text.length * 8;
  measurer.font = font;
  return measurer.measureText(text).width;
}

/**
 * Text on one line cut in the middle to the width it has, as SwiftUI's `truncationMode(.middle)`, with
 * the whole text one hover away. CSS only cuts the end, so the cut is measured here against the font
 * the element is drawn in; `maxWidth` is the room it may take.
 */
export function MiddleCut({ text, className }: { text: string; className?: string }) {
  const element = useRef<HTMLSpanElement>(null);
  const [shown, setShown] = useState(text);

  useLayoutEffect(() => {
    const span = element.current;
    const room = span?.parentElement;
    if (span === null || span === undefined || room === null || room === undefined) return;
    const fit = () => {
      const style = getComputedStyle(span);
      const font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
      // The room is the parent's content box less this element's own padding and border.
      const parent = getComputedStyle(room);
      const own = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight) + parseFloat(style.borderLeftWidth) + parseFloat(style.borderRightWidth);
      const width = room.clientWidth - parseFloat(parent.paddingLeft) - parseFloat(parent.paddingRight) - own;
      // A pixel of slack, since the room is rounded down to whole pixels and the text is not, and a text cut
      // for want of a fraction would shrink a container that hugs it, and be cut again.
      setShown(middleCut(text, (candidate) => measure(font, candidate) <= width + 1));
    };
    fit();
    const watcher = new ResizeObserver(fit);
    watcher.observe(room);
    return () => watcher.disconnect();
  }, [text]);

  return (
    <span ref={element} className={`whitespace-nowrap ${className ?? ''}`} title={text}>
      {shown}
    </span>
  );
}
