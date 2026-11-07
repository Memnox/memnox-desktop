import { LoaderCircle } from 'lucide-react';
import { KitLines } from '../../core/domain/kit-lines';

/** The console's small spinner, as the glyphs beside it are. */
const SPINNER_SIZE = 14;

/** A small spinner, the Mac's `ProgressView().controlSize(.small)`. */
export function Spinner({ size = SPINNER_SIZE, label = KitLines.working }: { size?: number; label?: string }) {
  return <LoaderCircle size={size} className="shrink-0 animate-spin text-muted" aria-label={label} />;
}
