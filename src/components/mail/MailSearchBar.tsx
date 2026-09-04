"use client";

import { Search } from "lucide-react";
import { settingsInputClass } from "@/components/ui/SettingsLayout";

interface MailSearchBarProps {
  value: string;
  onChange: (value: string) => void;
  onSubmit: () => void;
  disabled?: boolean;
}

export function MailSearchBar({
  value,
  onChange,
  onSubmit,
  disabled,
}: MailSearchBarProps) {
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit();
      }}
      className="relative"
    >
      <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        placeholder="Rechercher dans Gmail…"
        className={`${settingsInputClass} min-h-[2.75rem] pl-9 text-base lg:min-h-0 lg:text-sm`}
      />
    </form>
  );
}
