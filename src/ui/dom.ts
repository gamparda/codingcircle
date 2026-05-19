export function must<T extends Element>(selector: string, root: ParentNode = document): T {
  const element = root.querySelector(selector);
  if (!element) throw new Error(`Missing DOM element: ${selector}`);
  return element as T;
}

export function all<T extends Element>(selector: string, root: ParentNode = document): T[] {
  return [...root.querySelectorAll(selector)] as T[];
}
