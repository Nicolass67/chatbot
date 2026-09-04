import { redirect } from "next/navigation";

/** `/chat` n'a pas de page : on redirige vers une nouvelle conversation. */
export default function ChatIndexPage() {
  redirect("/chat/new");
}
