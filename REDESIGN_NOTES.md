# Dalabapay redesign — notes for building

## Before you build
1. Put your two logo files in `assets/images/`:
   - `assets/images/dabalogo.png` (the chevron mark)
   - `assets/images/dalabapay2.png` (mark + "Dalabapay" wordmark)
   The onboarding pictures are already there. No other image assets are used any more.
2. Run `flutter pub get`, then `flutter analyze` and fix anything it reports
   (this redesign could not be compiled where it was made — see below).
3. Bump `version:` in `pubspec.yaml` so the build number is higher than the
   one currently live on Google Play (e.g. `1.6.0+<live build + 1>`).
4. Put `secrets.json` (sent to you separately — never commit it) in the
   project folder, next to `pubspec.yaml`. Run and build with it:
   ```
   flutter run --dart-define-from-file=secrets.json
   flutter build appbundle --release --dart-define-from-file=secrets.json
   ```
   Without it the Paystack and VTpass keys are empty and payments fail.
   Keys it holds: `PAYSTACK_SECRET_KEY`, `VTPASS_API_KEY`, `VTPASS_SECRET_KEY`,
   `VTPASS_PUBLIC_KEY`, and the `VTPASS_SANDBOX_*` versions.
5. Sign with your existing upload keystore (`android/key.properties`).

## What changed
- New design system in `lib/ui/` (colours, Inter type, buttons, fields,
  chips, cards, banners, PIN boxes, keypad, bottom nav, review & receipt
  panels). `lib/core/theme/app_theme.dart` applies it app-wide.
- Redesigned: splash, onboarding, login (email **or phone**), sign-up with
  email code step, home, Pay bills hub, airtime, data, electricity, cable TV,
  international airtime, education, insurance, review payment + PIN,
  payment receipt, activity (with CSV export), commission & earnings,
  add money, **send money (wallet to wallet — new)**, profile, help &
  support (new), PIN setup / login / lock.
- Other screens (password reset, change PIN/password, notifications, KYC,
  referrals, disputes, payment validation, admin) keep their layout but use
  the new colours, font and theme.
- Payment, PIN, biometric and API logic is unchanged — screens call the same
  methods as before.

## Removed (no working backend)
- Tickets/flights (bookings were simulated — no money or booking happened)
- Betting wallet funding (`/api/betting/fund` does not exist)
- Donations (`/api/donations/make` does not exist)
- Virtual cards (no card provider)
- Dark mode and language switches (they had no effect)

## Needs the backend update (branch `redesign-backend-support`)
- Login with phone number
- "Estimated commission" (`GET /api/commission/rates`) — hidden if missing
- Send money name check (`POST /api/transfer/lookup`)

## Premium update (home, receipts, motion)
- **Home**: greeting header with avatar, notification count; gradient balance
  card with counting balance and four quick actions (Add money, Send, Pay
  bills, Activity); funding account number with copy; colourful Pay bills
  grid; "Earn while you pay" (earnings + invite code); recent activity card
  with status dots.
- **Receipts**: Dalabapay logo centred in the top bar; animated status mark
  (tick draws itself, ripples, sparks), counting amount, rows that cascade in,
  ticket-style dashed dividers.
- **Motion everywhere** (`lib/ui/dp_motion.dart`): page transitions for every
  screen, cards/banners/lists fade in, buttons and tiles press down, animated
  bottom-nav pill. All motion turns off when the phone's "Remove animations"
  setting is on.
