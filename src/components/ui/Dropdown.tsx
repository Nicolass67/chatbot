"use client";

import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { Spinner } from "@/components/ui/Spinner";

export interface DropdownOption<T extends string = string> {
  value: T;
  label: string;
  description?: string;
  disabled?: boolean;
}

interface DropdownProps<T extends string = string> {
  label: string;
  value: T;
  options: DropdownOption<T>[];
  onChange: (value: T) => void;
  disabled?: boolean;
  loading?: boolean;
  loadingLabel?: string;
  triggerLabel?: string;
  triggerTitle?: string;
  triggerClassName?: string;
  menuClassName?: string;
  align?: "start" | "end";
  placement?: "top" | "bottom";
  menuFullWidth?: boolean;
  wrapOptions?: boolean;
  icon?: ReactNode;
  compact?: boolean;
  className?: string;
}

export function Dropdown<T extends string = string>({
  label,
  value,
  options,
  onChange,
  disabled,
  loading,
  loadingLabel,
  triggerLabel,
  triggerTitle,
  triggerClassName,
  menuClassName,
  align = "start",
  placement = "top",
  menuFullWidth,
  wrapOptions,
  icon,
  compact,
  className,
}: DropdownProps<T>) {
  const [open, setOpen] = useState(false);
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const [menuPos, setMenuPos] = useState<{
    top?: number;
    bottom?: number;
    left?: number;
    right?: number;
    width?: number;
  }>({});
  const rootRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const triggerId = useId();
  const listId = useId();

  const active = options.find((o) => o.value === value);
  const displayLabel = loading
    ? loadingLabel ?? "Chargement…"
    : triggerLabel ?? active?.label ?? label;
  const displayTitle = loading
    ? undefined
    : triggerTitle ?? active?.label ?? triggerLabel;

  const updateMenuPos = useCallback(() => {
    const el = rootRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const width = menuFullWidth ? r.width : undefined;
    if (placement === "bottom") {
      setMenuPos({
        top: r.bottom + 6,
        left: align === "end" ? undefined : r.left,
        right: align === "end" ? window.innerWidth - r.right : undefined,
        width,
      });
    } else {
      setMenuPos({
        bottom: window.innerHeight - r.top + 6,
        left: align === "end" ? undefined : r.left,
        right: align === "end" ? window.innerWidth - r.right : undefined,
        width,
      });
    }
  }, [align, menuFullWidth, placement]);

  useLayoutEffect(() => {
    if (!open) return;
    updateMenuPos();
    const onScroll = () => updateMenuPos();
    window.addEventListener("resize", onScroll);
    window.addEventListener("scroll", onScroll, true);
    return () => {
      window.removeEventListener("resize", onScroll);
      window.removeEventListener("scroll", onScroll, true);
    };
  }, [open, updateMenuPos]);

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      const t = e.target as Node;
      if (rootRef.current?.contains(t)) return;
      if (listRef.current?.contains(t)) return;
      setOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, []);

  useEffect(() => {
    if (!open) {
      setFocusedIndex(-1);
      return;
    }
    const idx = options.findIndex((o) => o.value === value);
    setFocusedIndex(idx >= 0 ? idx : 0);
  }, [open, options, value]);

  const handleTriggerKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (disabled || loading) return;
      if (e.key === "Enter" || e.key === " " || e.key === "ArrowDown") {
        e.preventDefault();
        setOpen(true);
      }
    },
    [disabled, loading]
  );

  const handleListKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (options.filter((o) => !o.disabled).length === 0) return;

      if (e.key === "ArrowDown") {
        e.preventDefault();
        setFocusedIndex((i) => {
          const next = i + 1;
          return next >= options.length ? 0 : next;
        });
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setFocusedIndex((i) => {
          const prev = i - 1;
          return prev < 0 ? options.length - 1 : prev;
        });
      } else if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        const opt = options[focusedIndex];
        if (opt && !opt.disabled) {
          onChange(opt.value);
          setOpen(false);
        }
      } else if (e.key === "Escape") {
        setOpen(false);
      }
    },
    [focusedIndex, onChange, options]
  );

  useEffect(() => {
    if (open && focusedIndex >= 0 && listRef.current) {
      const el = listRef.current.querySelector(
        `[data-index="${focusedIndex}"]`
      ) as HTMLElement | null;
      el?.scrollIntoView({ block: "nearest" });
    }
  }, [focusedIndex, open]);

  const menu =
    open && !disabled && typeof document !== "undefined"
      ? createPortal(
          <div
            ref={listRef}
            id={listId}
            role="listbox"
            aria-label={label}
            tabIndex={-1}
            onKeyDown={handleListKeyDown}
            style={{
              position: "fixed",
              top: menuPos.top,
              bottom: menuPos.bottom,
              left: menuPos.left,
              right: menuPos.right,
              width: menuPos.width,
              zIndex: 200,
            }}
            className={cn(
              "glass-thick min-w-[200px] max-w-[min(320px,calc(100vw-2rem))] rounded-[var(--radius-xl)] p-1 text-foreground",
              "animate-[toast-in_var(--duration-normal)_var(--ease-out)_forwards]",
              menuClassName
            )}
          >
            <p className="px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider text-muted">
              {label}
            </p>
            <div className="max-h-56 overflow-y-auto">
              {options.map((option, index) => (
                <button
                  key={option.value}
                  type="button"
                  role="option"
                  data-index={index}
                  aria-selected={value === option.value}
                  disabled={option.disabled}
                  onClick={() => {
                    onChange(option.value);
                    setOpen(false);
                  }}
                  className={cn(
                    "flex w-full min-h-[36px] items-center gap-2.5 rounded-[var(--radius-md)] px-2.5 py-2 text-left text-sm text-foreground transition-colors hover:bg-surface-hover",
                    value === option.value && "bg-surface-hover",
                    focusedIndex === index &&
                      value !== option.value &&
                      "bg-surface-hover",
                    option.disabled && "cursor-not-allowed opacity-40"
                  )}
                >
                  <span
                    className={cn(
                      "h-2 w-2 shrink-0 rounded-full border border-border-strong",
                      value === option.value && "border-accent bg-accent"
                    )}
                    aria-hidden
                  />
                  <span className="min-w-0 flex-1">
                    <span
                      className={cn(
                        "block text-sm leading-snug text-foreground",
                        wrapOptions
                          ? "whitespace-normal break-words"
                          : "truncate"
                      )}
                      title={option.label}
                    >
                      {option.label}
                    </span>
                    {option.description && (
                      <span className="mt-0.5 block text-[11px] text-muted">
                        {option.description}
                      </span>
                    )}
                  </span>
                </button>
              ))}
            </div>
          </div>,
          document.body
        )
      : null;

  return (
    <div ref={rootRef} className={cn("relative", className)}>
      <button
        id={triggerId}
        type="button"
        disabled={disabled || loading || options.length === 0}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => !disabled && !loading && setOpen((o) => !o)}
        onKeyDown={handleTriggerKeyDown}
        title={displayTitle}
        className={cn(
          "inline-flex min-h-[32px] min-w-0 max-w-[9.5rem] items-center gap-1.5 rounded-[var(--radius-md)] px-2 py-1 text-[11px] text-muted transition-colors hover:bg-surface-hover hover:text-foreground sm:max-w-[11rem] md:min-h-0 md:max-w-[13rem] md:text-xs",
          open && "bg-surface-hover text-foreground",
          (disabled || loading) && "cursor-not-allowed opacity-50",
          compact && "max-w-[7.5rem]",
          triggerClassName
        )}
      >
        {icon}
        {loading && <Spinner size="sm" />}
        <span className="min-w-0 flex-1 truncate text-left">{displayLabel}</span>
        <ChevronDown
          className={cn(
            "h-3 w-3 shrink-0 opacity-60 transition-transform duration-[var(--duration-fast)]",
            open && "rotate-180"
          )}
        />
      </button>
      {menu}
    </div>
  );
}
