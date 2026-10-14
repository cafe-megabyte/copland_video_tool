// Browser media operations can remain pending without reporting an error.
export function withTimeout(operation, milliseconds, message) {
  let timer;
  return Promise.race([operation, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), milliseconds);
  })]).finally(() => clearTimeout(timer));
}
