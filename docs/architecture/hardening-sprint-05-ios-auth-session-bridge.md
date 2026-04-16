# Hardening Sprint 05: iOS Auth Session Bridge

## Date

2026-04-16

## Goal

Align the iOS client with the new backend refresh-session model so logout and startup auth recovery reflect real server session semantics instead of only local keychain state.

## Current Problems

### 1. Sign out is local only

`AuthViewModel.signOut()` clears keychain and UI state, but it does not call the backend logout endpoint. After the backend moved to revocable refresh sessions, this leaves the server session alive.

### 2. Startup auth state is stricter than background sync

`AuthViewModel.checkExistingAuth()` only treated an access token as authenticated, while background sync already treated either access or refresh token as recoverable auth state. That mismatch can cause the UI to show signed-out while background sync still considers the user authenticated.

## Design

### A. Introduce a single local auth-session predicate

Add `KeyChainManager.hasStoredSession`:

- true if access token exists
- true if refresh token exists
- false only when both are absent

Use this in both startup auth recovery and background sync bootstrap.

### B. Add explicit client logout API

Introduce `APIClient.logout(refreshToken:)`:

- `POST /api/v1/auth/logout`
- public endpoint
- sends only `refresh_token` in the body
- does not attach Bearer access token
- does not attempt refresh-on-401 recursion

This keeps logout semantics tied to the refresh session, which is the server-side revocation primitive.

### C. Make sign out best-effort remote, always local

`AuthViewModel.signOut()` becomes async and follows:

1. read current refresh token
2. if requested, call backend logout best-effort
3. regardless of network result, clear local tokens
4. clear current user
5. set auth state to signed out

This is the right trade-off for mobile UX:

- if network is available, revoke the backend session
- if network is unavailable, do not trap the user in a failed logout state

### D. Preserve local-only debug tooling

Debug-only “Clear Keychain” should skip remote revocation and only clear local auth state.

## Non-Goals

- No token refresh redesign on iOS; it already stores rotated token pairs.
- No multi-device session UI.
- No user-facing logout error surface.

## Test Strategy

### API client

- logout posts `refresh_token` to `/api/v1/auth/logout`
- logout does not send Authorization header
- missing refresh token returns `.unauthorized`

### Auth view model

- refresh-only keychain state can recover to signed-in on startup
- sign out revokes remote session and clears local state
- sign out still clears local state when network logout fails

### Keychain

- `hasStoredSession` is false when empty and true when tokens are present

## Outcome

After this sprint:

1. iOS logout can revoke backend refresh sessions.
2. UI auth recovery and background sync use the same notion of “recoverable session”.
3. Mobile logout remains reliable under poor network conditions.
