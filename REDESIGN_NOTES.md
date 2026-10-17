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
4. Build with your existing upload keystore (`android/key.properties`).

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
