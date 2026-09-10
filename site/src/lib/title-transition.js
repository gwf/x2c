// Captured from the local title studio's saved A and B settings.
export const titleTransition = {
  delay: 10000,
  duration: 16000,
  easing: ["smooth", "smooth"],
  a: {
    background: 100,
    lines: [
      { opacity: 100, blur: 0, depth: 0, softness: 100, strength: 40 },
      { opacity: 40, blur: 0, depth: 0, softness: 0, strength: 0 },
    ],
  },
  b: {
    background: 100,
    lines: [
      { opacity: 40, blur: 0, depth: 0, softness: 0, strength: 0 },
      { opacity: 100, blur: 0, depth: 0, softness: 100, strength: 40 },
    ],
  },
};

export function lineStyle(state) {
  const shadow = `0 ${.025 * state.depth / 100}em ` +
    `${.055 * state.softness / 100}em ` +
    `rgba(23,23,23,${state.strength / 100})`;
  return `color:rgba(23,23,23,${state.opacity / 100});` +
    `filter:blur(${state.blur / 1000}em);text-shadow:${shadow}`;
}

export function ease(t, curve) {
  if (curve === "in") return t * t;
  if (curve === "out") return 1 - (1 - t) * (1 - t);
  if (curve === "smooth") return t * t * (3 - 2 * t);
  return t;
}

export function titleState(t) {
  const { a, b, easing } = titleTransition;
  const lerp = (start, end, amount) => start + (end - start) * amount;
  return {
    background: lerp(a.background, b.background, ease(t, "smooth")),
    lines: a.lines.map((line, i) => Object.fromEntries(
      Object.keys(line).map(key => [key,
        lerp(line[key], b.lines[i][key], ease(t, easing[i])),
      ]))),
  };
}

export function backgroundColor(tone) {
  return `rgb(${[138, 132, 124].map((value, i) =>
    Math.round(value + ([244, 241, 236][i] - value) * tone / 100)
  ).join(",")})`;
}
