import { viewerAsset } from "../../../../lib/from-c-viewer";
export function getStaticPaths() {
  return ["diff", "app", "snapshots"].map(asset => ({params: {asset}}));
}
export const GET = ({params}) => viewerAsset(`${params.asset}.js`);
