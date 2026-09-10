// Captured from the local title studio's saved A and B settings.
export const titleTransition = {
  delay: 10000,
  duration: 16000,
  easing: ["smooth", "smooth"],
  a: {
    background: 100,
    lines: [
      { opacity: 100, blur: 0, depth: 0, softness: 100, strength: 30 },
      { opacity: 30, blur: 0, depth: 0, softness: 0, strength: 0 },
    ],
  },
  b: {
    background: 100,
    lines: [
      { opacity: 30, blur: 0, depth: 0, softness: 0, strength: 0 },
      { opacity: 100, blur: 0, depth: 0, softness: 100, strength: 30 },
    ],
  },
};

export function lineStyle(state) {
  const shadow = (y, blur, rgb, alpha) =>
    `0 ${y * state.depth / 100}em ${blur * state.softness / 100}em ` +
    `rgba(${rgb},${Math.min(1, alpha * state.strength / 100)})`;
  const shadows = [
    shadow(.008, .02, "23,23,23", .65),
    shadow(.025, .055, "23,23,23", .4),
    shadow(.065, .15, "23,23,23", .28),
  ];
  return `color:rgba(23,23,23,${state.opacity / 100});` +
    `filter:blur(${state.blur / 1000}em);text-shadow:${shadows.join(",")}`;
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
