declare global {
  interface Window {
    plausible?: (
      event: string,
      options: { props: Record<string, string> }
    ) => void;
  }
}

export function trackExampleAction(element: Element, action: string) {
  const example = element.closest<HTMLElement>("[data-example]");
  const surface = element.closest<HTMLElement>("[data-surface]");
  if (!example || !surface) return;

  try {
    window.plausible?.("Example action", { props: {
      example: example.dataset.example!,
      action,
      surface: surface.dataset.surface!,
    } });
  } catch {
    // Optional measurement must not interrupt navigation or copying.
  }
}

export function trackExampleSelect(element: Element, method: string) {
  const example = element.closest<HTMLElement>("[data-example]");
  const section = element.closest<HTMLElement>("[data-section]");
  if (!example || !section) return;

  try {
    window.plausible?.("Example select", { props: {
      example: example.dataset.example!,
      section: section.dataset.section!,
      method,
    } });
  } catch {
    // The example remains usable if measurement is unavailable.
  }
}
