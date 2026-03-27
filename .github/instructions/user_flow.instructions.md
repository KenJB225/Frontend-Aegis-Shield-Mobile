# Aegis-Dry User Flow (Mobile First)

## Scope
This instruction defines the primary end-user flow for the Flutter mobile app and the secondary superadmin web flow. The mobile app is the default user experience for device owners and operators.

## 1. Mobile Authentication and Session
1. User opens the Aegis-Dry mobile app.
2. App checks for an existing Supabase session.
3. If no session exists, user is routed to login/signup.
4. If a valid session exists, app loads the latest user profile and linked devices.
5. If `is_active` is false, access is blocked and user is prompted to contact admin.

## 2. Mobile Initialization Flow
1. Splash/initialization screen displays startup progress.
2. App verifies cloud connectivity and retrieves device state through Next.js API routes.
3. App loads latest sensor snapshots and recent event logs.
4. System checks whether user location is already configured.
5. If location is missing, user is routed to `Set Location` and cannot proceed to Home until saved.
6. When startup checks and location requirements succeed, app navigates to Home.

## 3. Mobile Home and Status Monitoring Flow
1. Home screen shows current system state (`Safe`, `Warning`, `Critical`) and device mode (`AUTO` or `MANUAL`).
2. User sees key metrics (rain, temperature, humidity, and other configured readings).
3. Device status (`DOCKED` or `EXTENDED`) and last update time are visible at a glance.
4. User can open deeper views for device control, logs, alerts, and settings.

## 4. Device Control and Manual Override Flow
1. User opens Device Control.
2. In `AUTO` mode, user monitors status and threshold behavior.
3. User may switch to `MANUAL` mode when override is required.
4. User sends `DOCK` or `EXTEND` command with optional reason/context.
5. App sends command intent through Next.js API, which logs the action via edge backend workflows.
6. Updated device state is reflected in realtime on the app.

## 5. Threshold Configuration Flow
1. User opens Settings or Device Configuration.
2. User updates precipitation threshold (0-100).
3. App validates input before save.
4. On successful update, Next.js API persists the new value and logs `THRESHOLD_UPDATED` via edge backend logic.

## 6. Location Management Flow
1. User opens Settings and selects `Change Location`.
2. App opens the location form screen prefilled with current coordinates.
3. User updates location label and latitude/longitude values.
4. App validates coordinate range before save.
5. On successful save, app refreshes weather/rain-probability data for the new location.

## 7. Alerts and Activity History Flow
1. User opens Alerts to review critical and warning events.
2. User opens Activity History to inspect chronological logs.
3. User filters/searches logs by date or event type.
4. Selecting an item reveals event details and system response context.

## 8. Mobile Logout Flow
1. User taps Logout in Settings or profile section.
2. App clears local session/token state.
3. User is routed back to the authentication screen.

## 9. Secondary Flow: Superadmin Web Panel
1. Superadmin signs in to the web dashboard.
2. Superadmin reviews dashboard metrics, user statuses, and audit activity.
3. Superadmin can enable/disable user access and review activity logs.
4. All admin actions are captured in `activity_logs` for auditability.

## 10. Cross-Flow Operational Rules
1. Mobile users only access their own records through RLS-protected data paths.
2. Superadmin privileges must be role-gated (`SUPER_ADMIN`) and never exposed in mobile UI.
3. Mobile and device clients should use Next.js API routes for operational commands and data requests.
4. Next.js API routes must invoke Supabase Edge Functions for backend decision logic and privileged writes.
5. Device status, threshold changes, and manual overrides must produce traceable log entries.
6. Location setup is mandatory before weather-driven automation screens are accessible.
7. Realtime updates should keep Home, Alerts, and Logs synchronized with backend state.