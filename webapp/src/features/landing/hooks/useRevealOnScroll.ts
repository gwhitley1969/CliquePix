import { useEffect, useRef, useState } from 'react';

/**
 * One-shot IntersectionObserver hook. Returns a ref and a `revealed` flag
 * that flips to true the first time the element enters the viewport. Used
 * for the landing page's gentle fade-in-on-scroll effect. Honors
 * `prefers-reduced-motion` by resolving to revealed=true on mount so nothing
 * ever hides for users who've disabled animation.
 */
export function useRevealOnScroll<T extends HTMLElement = HTMLDivElement>(options?: {
  rootMargin?: string;
  threshold?: number;
}) {
  const ref = useRef<T | null>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) {
      setRevealed(true);
      return;
    }

    const node = ref.current;
    if (!node) return;
    if (typeof IntersectionObserver === 'undefined') {
      // Ancient browser — reveal immediately rather than hide forever.
      setRevealed(true);
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setRevealed(true);
            observer.disconnect();
            break;
          }
        }
      },
      {
        rootMargin: options?.rootMargin ?? '0px 0px -10% 0px',
        threshold: options?.threshold ?? 0.15,
      },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [options?.rootMargin, options?.threshold]);

  return { ref, revealed };
}
