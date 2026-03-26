export default oauthKeycloakEventHandler({
  async onSuccess(event, { user, tokens }) {
    await setUserSession(event, {
      user: {
        email: user.email,
        name: user.name || `${user.given_name || ''} ${user.family_name || ''}`.trim(),
        preferred_username: user.preferred_username,
        sub: user.sub,
        roles: user.realm_access?.roles || [],
      },
      accessToken: tokens.access_token,
    })
    return sendRedirect(event, '/clara')
  },
  onError(event, error) {
    console.error('Keycloak OAuth error:', error)
    return sendRedirect(event, '/login?error=auth_failed')
  },
})
