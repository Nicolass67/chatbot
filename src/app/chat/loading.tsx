export default function ChatLoading() {
  return (
    <div
      data-workspace="chat-loading"
      className="flex h-dvh bg-zinc-950 text-zinc-100"
    >
      <aside className="hidden w-64 flex-col border-r border-zinc-800 p-3 md:flex">
        <div className="mb-4 h-6 w-28 animate-pulse rounded bg-zinc-800" />
        <div className="mb-6 flex gap-2">
          <div className="h-7 w-14 animate-pulse rounded bg-zinc-800" />
          <div className="h-7 w-14 animate-pulse rounded bg-zinc-800" />
          <div className="h-7 w-14 animate-pulse rounded bg-zinc-800" />
        </div>
        <div className="space-y-2">
          {Array.from({ length: 10 }).map((_, i) => (
            <div
              key={i}
              className="h-9 animate-pulse rounded-md bg-zinc-900/80"
            />
          ))}
        </div>
      </aside>
      <main className="flex min-w-0 flex-1 flex-col">
        <div className="border-b border-zinc-800 px-4 py-3">
          <div className="h-5 w-48 animate-pulse rounded bg-zinc-800" />
        </div>
        <div className="flex-1" />
        <div className="border-t border-zinc-800 p-4">
          <div className="h-12 animate-pulse rounded-xl bg-zinc-900" />
        </div>
      </main>
    </div>
  );
}
