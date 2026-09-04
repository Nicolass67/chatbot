export default function MailLoading() {
  return (
    <div
      data-workspace="mail-loading"
      className="flex h-dvh flex-col bg-zinc-950 text-zinc-100"
    >
      <div className="flex items-center gap-3 border-b border-zinc-800 px-4 py-3">
        <div className="h-4 w-16 animate-pulse rounded bg-zinc-800" />
        <div className="h-4 w-16 animate-pulse rounded bg-zinc-800" />
        <div className="h-4 w-16 animate-pulse rounded bg-zinc-800" />
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="w-full max-w-md space-y-2 border-r border-zinc-800 p-3">
          {Array.from({ length: 8 }).map((_, i) => (
            <div
              key={i}
              className="h-14 animate-pulse rounded-md bg-zinc-900/80"
            />
          ))}
        </div>
        <div className="hidden flex-1 p-6 lg:block">
          <div className="mb-4 h-6 w-48 animate-pulse rounded bg-zinc-800" />
          <div className="space-y-2">
            <div className="h-3 w-full animate-pulse rounded bg-zinc-900" />
            <div className="h-3 w-5/6 animate-pulse rounded bg-zinc-900" />
            <div className="h-3 w-4/6 animate-pulse rounded bg-zinc-900" />
          </div>
        </div>
      </div>
    </div>
  );
}
