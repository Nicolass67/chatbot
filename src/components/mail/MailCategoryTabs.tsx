"use client";

import { cn } from "@/lib/utils/cn";
import {
  MAIL_CATEGORIES,
  type MailCategory,
} from "@/lib/mail/categories";

const SCOPE_IDS = new Set<MailCategory>(["unread", "inbox"]);

const GMAIL_TABS = MAIL_CATEGORIES.filter((c) => !SCOPE_IDS.has(c.id));

interface MailCategoryTabsProps {
  active: MailCategory;
  onChange: (category: MailCategory) => void;
  disabled?: boolean;
  /** @deprecated Les scopes Non lus / Boîte sont toujours affichés. */
  includeNavCategories?: boolean;
}

export function MailCategoryTabs({
  active,
  onChange,
  disabled,
}: MailCategoryTabsProps) {
  const scopeActive = SCOPE_IDS.has(active);

  return (
    <div className="border-b border-border-subtle px-3 py-2 lg:space-y-2.5 lg:py-2.5">
      {/* Scopes: desktop only — mobile = header */}
      <div
        role="group"
        aria-label="Portée de la boîte"
        className="mb-2.5 hidden gap-4 lg:flex"
      >
        <button
          type="button"
          disabled={disabled}
          onClick={() => onChange("inbox")}
          className={cn(
            "min-h-8 border-b-2 pb-1 text-[13px] transition-colors",
            active === "inbox"
              ? "border-accent font-semibold text-foreground"
              : "border-transparent text-muted hover:text-foreground"
          )}
        >
          Boîte
        </button>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onChange("unread")}
          className={cn(
            "min-h-8 border-b-2 pb-1 text-[13px] transition-colors",
            active === "unread"
              ? "border-accent font-semibold text-foreground"
              : "border-transparent text-muted hover:text-foreground"
          )}
        >
          Non lus
        </button>
      </div>

      <div
        role="tablist"
        aria-label="Catégories Gmail"
        className="flex flex-nowrap gap-1 overflow-x-auto scroll-smooth [scrollbar-width:thin]"
      >
        {GMAIL_TABS.map((category) => {
          const selected = !scopeActive && active === category.id;
          return (
            <button
              key={category.id}
              type="button"
              role="tab"
              aria-selected={selected}
              disabled={disabled}
              onClick={() => onChange(category.id)}
              className={cn(
                "shrink-0 rounded-[var(--radius-sm)] px-2 py-1 text-[12px] transition-colors",
                "min-h-7 touch-manipulation whitespace-nowrap",
                selected
                  ? "bg-accent-subtle font-medium text-accent"
                  : "text-muted hover:bg-surface-hover hover:text-foreground"
              )}
            >
              {category.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}
