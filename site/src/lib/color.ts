/** Relative luminance of a #rrggbb colour, per WCAG 2. */
export function luminance(hex: string): number {
  const n = parseInt(hex.slice(1), 16);
  const channel = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
}

/** Near-black or white, whichever reads better on the given fill. */
export function inkOn(hex: string): '#0a0b0d' | '#ffffff' {
  const l = luminance(hex);
  const onWhite = 1.05 / (l + 0.05);
  const onDark = (l + 0.05) / (luminance('#0a0b0d') + 0.05);
  return onDark >= onWhite ? '#0a0b0d' : '#ffffff';
}
