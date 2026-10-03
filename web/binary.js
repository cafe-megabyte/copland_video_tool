export const bytes = (...values) => Uint8Array.from(values.flat());
export const text = value => Uint8Array.from([...value].map(c => c.charCodeAt(0)));
export function join(...parts) {
  const size = parts.reduce((n, p) => n + p.length, 0);
  const result = new Uint8Array(size); let offset = 0;
  for (const part of parts) { result.set(part, offset); offset += part.length; }
  return result;
}
export function uint(value, length = 4) {
  if (!Number.isSafeInteger(value) || value < 0 || value >= 2 ** (length * 8)) throw new Error('error.numberRange');
  const result = new Uint8Array(length);
  for (let i = length - 1; i >= 0; --i) { result[i] = value % 256; value = Math.floor(value / 256); }
  return result;
}
export const box = (type, ...parts) => { const payload = join(...parts); return join(uint(payload.length + 8), text(type), payload); };
export const fullBox = (type, flags, ...parts) => box(type, uint(flags), ...parts);
export const timestamp = (index, fps) => Math.round(index * 1000000 / fps);
