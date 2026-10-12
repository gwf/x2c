importScripts("layout.js");
onmessage = ({ data }) => {
  try {
    postMessage({
      layout: GraphLayout.solve(data.groups, data.edges, data.aspect),
    });
  } catch (e) {
    postMessage({ error: e.message });
  }
};
