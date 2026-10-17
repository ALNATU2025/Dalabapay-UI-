# Images to create for the new design

Put every file in **`assets/images/`**, with exactly the file names below.
The app already works without them: each missing image shows a clean icon
instead, and the real picture appears as soon as you add the file.
No code or `pubspec.yaml` changes are needed.

**Format for all:** PNG with a transparent background.

## Already have (keep)
| File | Shows on |
|---|---|
| `dabalogo.png` | Splash, login, About Dalabapay |
| `dalabapay2.png` | Receipts, logo bar |

## 1. Onboarding illustrations — 3 files
Size **1080 × 1080 px**, character/object centred, transparent background.

| File | Slide | What to draw |
|---|---|---|
| `onboarding_1.png` | Manage Your Wallet & Pay Bills | Person holding a phone, with floating wallet, lightning and bill icons |
| `onboarding_2.png` | Instant Payments, 24/7 | "24/7" badge with phone showing airtime/data/TV/electricity being paid instantly (no POS — there's no POS service yet) |
| `onboarding_3.png` | Earn As You Pay | Coins / gift box / phone showing earnings |

## 2. Service icons (3D style) — 12 files
Size **256 × 256 px**, icon centred with ~10% empty space around it.

| File | Tile |
|---|---|
| `svc_airtime.png` | Airtime |
| `svc_data.png` | Data |
| `svc_tv.png` | TV / TV Packages |
| `svc_electricity.png` | Electricity |
| `svc_bills.png` | Bills / Pay Bills |
| `svc_insurance.png` | Insurance |
| `svc_education.png` | Education |
| `svc_international.png` | International Airtime |
| `svc_add_money.png` | Add Money (All Services) |
| `svc_send_money.png` | Send Money (All Services) |
| `svc_earnings.png` | Earnings (All Services) |
| `svc_more.png` | More |

## 3. Provider logos — 8 files
Size **256 × 256 px**, square. Use the official logos.

| File | Shows on |
|---|---|
| `provider_mtn.png` | Airtime & Data network picker |
| `provider_airtel.png` | Airtime & Data network picker |
| `provider_glo.png` | Airtime & Data network picker |
| `provider_9mobile.png` | Airtime & Data network picker |
| `provider_dstv.png` | Pay Bills, Cable TV picker |
| `provider_gotv.png` | Pay Bills, Cable TV picker |
| `provider_startimes.png` | Pay Bills, Cable TV picker |
| `provider_waec.png` | Pay Bills, All Services (WAEC PIN) |

## 4. Promo banner art — 2 files
Size **420 × 360 px**, transparent background (sits on the navy banner).

| File | Banner |
|---|---|
| `banner_refer.png` | Home → "Refer a Friend" (gift box) |
| `banner_bills.png` | Pay Bills → "Quick & Easy Bill Payments" (bill + lightning) |

**Total: 25 new images** (3 + 12 + 8 + 2).

After adding them: `flutter clean`, then run the app again.
