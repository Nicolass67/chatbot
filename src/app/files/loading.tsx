export default function FilesLoading() {
  return (
    <div
      data-workspace="files-loading"
      className="flex h-dvh flex-col bg-zinc-950 text-zinc-100"
    >
      <div className="flex items-center gap-3 border-b border-zinc-800 px-4 py-3">
        <div className="h-4 w-16 animate-pulse rounded bg-zinc-800" />
        <div className="h-4 w-20 animate-pulse rounded bg-zinc-800" />
        <div className="h-8 flex-1 animate-pulse rounded bg-zinc-900" />
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="hidden w-56 space-y-2 border-r border-zinc-800 p-3 md:block">
          {Array.from({ length: 5 }).map((_, i) => (
            <div
              key={i}
              className="h-8 animate-pulse rounded bg-zinc-900/80"
            />
          ))}
        </div>
        <div className="grid flex-1 grid-cols-2 gap-3 p-4 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 12 }).map((_, i) => (
            <div
              key={i}
              className="aspect-square animate-pulse rounded-lg bg-zinc-900/80"
            />
          ))}
        </div>
      </div>
    </div>
  );
}
