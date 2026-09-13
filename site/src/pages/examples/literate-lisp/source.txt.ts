import type { APIRoute } from "astro";
import source from "../../../../../examples/programs/literate-lisp.x?raw";

export const GET: APIRoute = () => new Response(source, {
  headers: { "Content-Type": "text/plain; charset=utf-8" },
});
