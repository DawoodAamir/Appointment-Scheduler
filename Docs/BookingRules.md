# Booking and calendar rules

Appointments use half-open intervals: `[start, end)`. A 10:00–10:30 booking permits another at 10:30. Confirmed and tentative bookings occupy time. Cancelled bookings remain in history and do not block availability. Editing excludes the booking’s own UUID from conflict checks.

Business hours are Monday–Friday, 09:00–17:00 in the current calendar/time zone. A booking must fit completely within those hours. Available starts advance by 15 minutes and omit past starts; the editor permits manually entering historical records. All saves use the same validation, including duration limits of 15–180 minutes.

The example models a single resource. Add resource IDs and include them in overlap queries before adapting this to multiple staff members. Concurrent booking from multiple devices would require server-side transactions; local validation alone is not sufficient.

## Calendar files

Exports contain one VEVENT with a stable UID derived from the booking UUID. Dates are written in UTC, user text is escaped, and lines are folded at 75 UTF-8 octets without splitting a scalar. Notes are included, contact details are not. Exported files do not send invitations, update a server, or automatically remove previously imported events.

## Reminder review

- Deny notification permission and save a reminder-enabled booking; the booking must remain saved.
- Grant permission and create a booking more than 15 minutes away.
- Edit its start time and verify only the new reminder remains pending.
- Cancel it and verify the pending request is removed.
- Reopen the app with several future bookings and verify reconciliation.
- Check device delivery with Focus and notification settings understood.

The app uses generic reminder text, caps the queue at 60 upcoming reminders, and refreshes when foregrounded. Calendar clients and the OS remain responsible for import and notification behavior.
