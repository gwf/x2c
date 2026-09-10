import { trackExampleSelect } from "./analytics";

const fragmentId = (hash: string) => {
  try {
    return decodeURIComponent(hash.slice(1));
  } catch {
    return "";
  }
};
const destinations = new Map<string, () => void>();

for (const carousel of document.querySelectorAll<HTMLElement>(
  "[data-carousel]",
)) {
  const track = carousel.querySelector<HTMLElement>("[data-carousel-track]")!;
  const tabs = [...carousel.querySelectorAll<HTMLButtonElement>(
    "[data-carousel-tab]",
  )];
  const tablist = carousel.querySelector<HTMLElement>(".carousel-tabs")!;
  const slides = [...track.children] as HTMLElement[];
  const count = carousel.querySelector<HTMLElement>("[data-carousel-count]")!;
  let index = -1;
  let pointerStart: number | null = null;

  // Scroll only the tab strip; scrollIntoView can also move the document.
  const revealTab = () => {
    const tab = tabs[index];
    const left = tab.getBoundingClientRect().left -
      tablist.getBoundingClientRect().left + tablist.scrollLeft;
    const right = left + tab.offsetWidth;
    if (left < tablist.scrollLeft) tablist.scrollLeft = left;
    else if (right > tablist.scrollLeft + tablist.clientWidth)
      tablist.scrollLeft = right - tablist.clientWidth;
  };

  const show = (
    next: number,
    method?: string,
    focus = false,
    updateUrl = true,
  ) => {
    const selected = (next + slides.length) % slides.length;
    const changed = selected !== index;
    index = selected;
    track.style.transform = `translateX(-${index * 100}%)`;
    count.textContent =
      `${String(index + 1).padStart(2, "0")} / ` +
      String(slides.length).padStart(2, "0");

    tabs.forEach((tab, position) => {
      const active = position === index;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
      slides[position].setAttribute("aria-hidden", String(!active));
      slides[position].toggleAttribute("inert", !active);
    });

    if (carousel.hasAttribute("data-carousel-ready")) revealTab();
    if (focus) tabs[index].focus({ preventScroll: true });
    if (method && updateUrl) {
      const url = new URL(location.href);
      url.hash = slides[index].id;
      history.replaceState(history.state, "", url);
    }
    if (method && changed) trackExampleSelect(slides[index], method);
  };

  slides.forEach((slide, position) => {
    destinations.set(slide.id, () => {
      show(position, "link", false, false);
      carousel.scrollIntoView({ block: "start", behavior: "instant" });
    });
  });

  tabs.forEach((tab, position) => {
    tab.addEventListener("click", () => show(position, "tab"));
    tab.addEventListener("keydown", (event) => {
      let next: number;
      if (event.key === "ArrowRight") next = index + 1;
      else if (event.key === "ArrowLeft") next = index - 1;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = slides.length - 1;
      else return;
      event.preventDefault();
      show(next, "keyboard", true);
    });
  });
  carousel.querySelector("[data-carousel-prev]")!
    .addEventListener("click", () => show(index - 1, "previous"));
  carousel.querySelector("[data-carousel-next]")!
    .addEventListener("click", () => show(index + 1, "next"));

  const viewport = track.parentElement!;
  viewport.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "mouse") pointerStart = event.clientX;
  });
  viewport.addEventListener("pointerup", (event) => {
    if (pointerStart === null) return;
    const distance = event.clientX - pointerStart;
    pointerStart = null;
    if (Math.abs(distance) > 48)
      show(index + (distance < 0 ? 1 : -1), "swipe");
  });
  viewport.addEventListener("pointercancel", () => { pointerStart = null; });

  const initial = slides.findIndex((slide) =>
    slide.id === fragmentId(location.hash));
  show(initial < 0 ? 0 : initial, initial < 0 ? undefined : "link", false, false);
  carousel.setAttribute("data-carousel-ready", "");
  count.setAttribute("aria-live", "polite");
  revealTab();

  const updateTabFades = () => {
    tablist.toggleAttribute("data-hidden-left", tablist.scrollLeft > 1);
    tablist.toggleAttribute("data-hidden-right",
      tablist.scrollWidth - tablist.clientWidth - tablist.scrollLeft > 1);
  };
  tablist.addEventListener("scroll", updateTabFades, { passive: true });
  const updateTabLayout = () => {
    revealTab();
    updateTabFades();
  };
  new ResizeObserver(updateTabLayout).observe(tablist);
  document.fonts.ready.then(updateTabLayout);
  updateTabFades();
}

const followFragment = () => destinations.get(fragmentId(location.hash))?.();
window.addEventListener("hashchange", followFragment);
window.addEventListener("popstate", followFragment);

document.addEventListener("click", (event) => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey ||
      event.ctrlKey || event.shiftKey || event.altKey) return;
  const anchor = (event.target as Element).closest<HTMLAnchorElement>("a[href]");
  if (!anchor || anchor.target || anchor.hasAttribute("download")) return;
  const url = new URL(anchor.href);
  if (url.origin !== location.origin || url.pathname !== location.pathname ||
      url.search !== location.search) return;
  const follow = destinations.get(fragmentId(url.hash));
  if (!follow) return;
  event.preventDefault();
  if (url.hash !== location.hash) history.pushState(history.state, "", url);
  follow();
});

// Correct the native fragment scroll after stacked panels become a carousel.
if (document.readyState === "complete") followFragment();
else window.addEventListener("load", followFragment, { once: true });
