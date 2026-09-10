import type { APIRoute } from "astro";

const sources = import.meta.glob(
  "../../../../../examples/magic/tic-tac-toe.*",
  { query: "?raw", import: "default", eager: true },
);

export function getStaticPaths() {
  return Object.entries(sources).map(([path, source]) => ({
    params: { file: path.split("/").pop() },
    props: { source },
  }));
}

export const GET: APIRoute = ({ props }) => new Response(props.source, {
  headers: { "Content-Type": "text/plain; charset=utf-8" },
});
