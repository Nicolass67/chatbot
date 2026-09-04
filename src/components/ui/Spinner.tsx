import { cn } from "@/lib/utils/cn";

interface SpinnerProps {
  size?: "sm" | "md";
  className?: string;
}

const sizeStyles = {
  sm: "h-3.5 w-3.5 border-[1.5px]",
  md: "h-4 w-4 border-2",
};

export function Spinner({ size = "md", className }: SpinnerProps) {
  return (
    <span
      role="status"
      aria-hidden="true"
      className={cn(
        "inline-block animate-spin rounded-full border-border-strong border-t-foreground",
        sizeStyles[size],
        className
      )}
    />
  );
}
