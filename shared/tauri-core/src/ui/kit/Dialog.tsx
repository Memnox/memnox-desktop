import { Trash2, type LucideIcon } from 'lucide-react';
import { useEffect, type ReactNode } from 'react';
import { KitLines } from '../../core/domain/kit-lines';
import { Button } from './Button';

/** The confirm's tinted icon, as `ConsoleConfirm` draws it. */
const CONFIRM_ICON = 20;

/** Escape closes whatever sits over the page, as it does on the Mac. */
function useEscape(close: () => void) {
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [close]);
}

/**
 * Where something over the page sits: a `sheet` hangs from near the top and scrolls with a tall body, a `confirm`
 * sits in the middle on a blurred dim, and a `palette` hangs a little lower with no scroll of its own.
 */
export type ModalPlace = 'sheet' | 'confirm' | 'palette';

/** `ModalMetrics`: every console dialog blurs the window 8 behind it and dims it to 55%. */
const MODAL_SCRIM: Record<ModalPlace, string> = {
  sheet: 'fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/55 px-4 py-[8vh] backdrop-blur-sm',
  confirm: 'fixed inset-0 z-50 grid place-items-center bg-black/55 p-4 backdrop-blur-sm',
  palette: 'fixed inset-0 z-50 flex items-start justify-center bg-black/40 px-4 pt-[12vh]',
};

/** The card every modal is drawn on: radius 12, the panel edge, and the console's lift (0.18 black, radius 30, 12 down). */
const MODAL_CARD = 'flex flex-col rounded-card border border-panel-edge bg-card shadow-lift';

/** The card's width and how it holds a body taller than the window. */
const MODAL_SHAPE: Record<ModalPlace, string> = {
  sheet: 'w-full max-w-sheet min-h-[360px]',
  confirm: 'w-[440px] max-w-full gap-4 p-7',
  palette: 'w-full max-w-sheet overflow-hidden',
};

/**
 * Something over the page that holds it until it is closed: by Escape, by a press outside it, or by its own
 * Cancel. `Dialog` and `ConfirmDialog` are built on it; a page reaches for it only for a modal with neither shape.
 */
export function Modal({
  label,
  close,
  place = 'sheet',
  alert = false,
  className,
  children,
}: {
  label: string;
  close: () => void;
  place?: ModalPlace;
  /** Asks before something that cannot be undone, so a screen reader announces it at once. */
  alert?: boolean;
  /** Only for what the card holds beyond its shape, such as a cap on its height. */
  className?: string;
  children: ReactNode;
}) {
  useEscape(close);
  return (
    <div className={MODAL_SCRIM[place]} role="presentation" onMouseDown={close}>
      <div
        role={alert ? 'alertdialog' : 'dialog'}
        aria-modal="true"
        aria-label={label}
        className={`${MODAL_CARD} ${MODAL_SHAPE[place]} ${className ?? ''}`}
        onMouseDown={(event) => event.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}

/**
 * A sheet over the page, as the Mac's `SkillSheetFrame`: its title 18 semibold in a 56 bar, a hairline, the body
 * scrolling 20 inside with 16 between its parts, a hairline, and a foot 12 tall each side that leads with Cancel.
 * Like the Mac's sheet it has no close mark; Escape and Cancel close it. With `description` the head is the rule
 * dialogs': the title over its line, 16 above and below, the body 20 between its parts, and `even` shares the foot
 * equally between Cancel and the press. With `step` the step sits at the title's end.
 */
export function Dialog({
  title,
  description,
  step,
  close,
  cancel = KitLines.cancel,
  actions,
  even = false,
  children,
}: {
  title: string;
  description?: string;
  step?: string;
  close: () => void;
  /** The words on the leading press, Close where nothing would be lost, or null where a stage has nothing to cancel. */
  cancel?: string | null;
  /** What follows Cancel in the foot, the confirming press last. */
  actions?: ReactNode;
  even?: boolean;
  children: ReactNode;
}) {
  return (
    <Modal label={title} close={close} className="max-h-sheet overflow-hidden">
      {description === undefined ? (
        <header className="flex h-14 shrink-0 items-center gap-3 border-b border-panel-edge px-5">
          <span className="flex-1 text-lg font-semibold text-foreground">{title}</span>
          {step !== undefined && <span className="truncate text-footnote text-muted">{step}</span>}
        </header>
      ) : (
        <header className="flex shrink-0 flex-col gap-1 border-b border-panel-edge px-5 py-4">
          <span className="text-lg font-semibold text-foreground">{title}</span>
          <span className="text-footnote text-muted">{description}</span>
        </header>
      )}
      <div className={`flex min-h-0 flex-1 flex-col overflow-y-auto p-5 ${description === undefined ? 'gap-4' : 'gap-5'}`}>{children}</div>
      <footer className="flex shrink-0 items-center gap-2 border-t border-panel-edge px-5 py-3">
        {cancel !== null && (
          <Button wide={even} className={even ? 'flex-1' : undefined} onClick={close}>
            {cancel}
          </Button>
        )}
        {actions}
      </footer>
    </Modal>
  );
}

/** Whether the press a confirm asks for can be undone: red where it cannot, the brand blue where it can. */
export type ConfirmTone = 'danger' | 'neutral';

const CONFIRM_TINT: Record<ConfirmTone, string> = {
  danger: 'bg-destructive/[0.16] text-destructive',
  neutral: 'bg-primary/[0.16] text-primary',
};

/**
 * The console's confirm, as the Mac's `ConsoleConfirm`: a tinted icon, the question and what it costs, anything more
 * under it, then Cancel and the press itself side by side, in red where it cannot be undone.
 */
export function ConfirmDialog({
  icon: Icon = Trash2,
  title,
  message,
  detail,
  confirm,
  tone = 'danger',
  busy = false,
  aside,
  cancel,
  act,
}: {
  icon?: LucideIcon;
  title: string;
  message: string;
  /** What follows from it, under the message in the same muted words. */
  detail?: ReactNode;
  /** A quieter way out that goes somewhere instead of only closing, such as reading first. */
  aside?: { label: string; act: () => void };
  confirm: string;
  tone?: ConfirmTone;
  busy?: boolean;
  cancel: () => void;
  act: () => void;
}) {
  return (
    <Modal label={title} close={cancel} place="confirm" alert>
      <span className={`grid size-12 place-items-center rounded-card ${CONFIRM_TINT[tone]}`} aria-hidden>
        <Icon size={CONFIRM_ICON} strokeWidth={2} />
      </span>
      <div className="flex flex-col gap-2 text-body-sm">
        <h3 className="text-lg font-semibold text-foreground">{title}</h3>
        <p className="text-muted">{message}</p>
        {detail !== undefined && <div className="text-muted">{detail}</div>}
      </div>
      {aside !== undefined && (
        <Button kind="link" className="self-start" onClick={aside.act}>
          {aside.label}
        </Button>
      )}
      <div className="flex gap-2 pt-1.5">
        <Button wide className="flex-1" onClick={cancel}>
          {KitLines.cancel}
        </Button>
        <Button kind={tone === 'danger' ? 'danger' : 'primary'} wide className="flex-1" autoFocus disabled={busy} onClick={act}>
          {confirm}
        </Button>
      </div>
    </Modal>
  );
}
