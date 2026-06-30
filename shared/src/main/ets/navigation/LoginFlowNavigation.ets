/**
 * Close the login flow after a successful account capture.
 *
 * Login can be reached as Settings -> AccountLogin -> Method, or
 * Account -> AccountLogin -> Method when adding another account. A single pop only returns to the
 * method chooser, so close both login routes and show Account unless it is already underneath.
 */
export function closeLoginFlowToAccount(stack: NavPathStack): void {
  const names: string[] = stack.getAllPathName()
  const top: string = names.length > 0 ? names[names.length - 1] : ''
  const parent: string = names.length > 1 ? names[names.length - 2] : ''
  const grandParent: string = names.length > 2 ? names[names.length - 3] : ''

  if (top.length > 0) {
    stack.pop()
  }

  if (parent === 'AccountLogin') {
    stack.pop()
    if (grandParent !== 'Account') {
      stack.pushPathByName('Account', null)
    }
    return
  }

  if (parent !== 'Account') {
    stack.pushPathByName('Account', null)
  }
}

export function isTopRoute(stack: NavPathStack, name: string): boolean {
  const names: string[] = stack.getAllPathName()
  return names.length > 0 && names[names.length - 1] === name
}
