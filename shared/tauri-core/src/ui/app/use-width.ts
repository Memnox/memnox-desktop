import { useEffect, useState } from 'react';
import { widthClass, type WidthClass } from '../../core/domain/destinations';

/** The window's width class, read again whenever the window is resized. */
export function useWidthClass(): WidthClass {
  const [current, setCurrent] = useState(() => widthClass(window.innerWidth));
  useEffect(() => {
    const resized = () => setCurrent(widthClass(window.innerWidth));
    window.addEventListener('resize', resized);
    return () => window.removeEventListener('resize', resized);
  }, []);
  return current;
}
