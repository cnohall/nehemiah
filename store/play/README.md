# Google Play listing — com.fivestones.nehemiah

Everything the Play Console asks for, in the fastlane layout (`metadata/<locale>/`), so it
can be pasted by hand now and pushed by script later.

| Locale | Play language | Game language |
|---|---|---|
| en-US | English (United States) | en |
| es-419 | Spanish (Latin America) | es |
| pt-BR | Portuguese (Brazil) | pt_BR |
| de-DE | German | de |
| ko-KR | Korean | ko |

Only the five languages the game itself ships in: a listing in a language the game
doesn't speak would promise something the app can't keep.

Per locale: `title.txt` (≤30), `short_description.txt` (≤80), `full_description.txt`
(≤4000), `images/phoneScreenshots/1–6.png` (1920×1080), `images/featureGraphic.png`
(1024×500), `images/icon.png` (512×512).

## Regenerating the graphics

1. Captures (phone layout, touch HUD), from the `mobile-spike` worktree, once per language:
   `Godot --path . --resolution 1848x822 --script res://tools/store_shots.gd -- --touch --lang=<en|es|pt_BR|de|ko> <dir>`
   Godot hangs on exit (EOS): kill it once the six `shot` lines are printed.
   Copy `<dir>/<lang>/*.png` into `captures/<lang>/`.
2. `node store/play/render.mjs` (needs Chrome) frames and captions them from `captions.json`
   and renders the feature graphic from `feature_art.png`.

## App content answers (Play Console → Policy → App content)

**Privacy policy:** https://www.nehemiahgame.com/privacy (covers the Android app and Epic
Online Services). It still needs a contact email: set `CONTACT_EMAIL` on the website.

**Ads:** No.

**App access:** All functionality is available without special access (no login).

**Target audience:** 13 and over. Choosing under-13 age groups puts the app in the Families
program, whose SDK rules Epic Online Services would have to be checked against first.

**Content rating (IARC questionnaire):** category *Game*.
- Violence: yes, but not realistic: cartoon figures, slings and a short sword; enemies fall
  and fade, no blood or gore. Violence against human-like characters: yes.
- Fear, sexuality, language, controlled substances, gambling: no.
- Users can interact online: yes (co-op with up to three others by room code). No text or
  voice chat, no user-generated content, no sharing of location or personal info.
- Digital purchases: no.
Expect roughly PEGI 7 / ESRB Everyone 10+.

**Data safety:**
- Does the app collect or share user data? **Yes**: Epic Online Services, built in for
  online play, receives an anonymous device identifier when the app starts.
- Data type: **Device or other IDs** → collected, **not shared** (Epic processes it as a
  service provider), not ephemeral, **required** (the app signs in at launch), purpose
  **App functionality**.
- Encrypted in transit: **Yes**. Deletion requests: via the contact on the privacy page.
- Nothing else: no location, personal info, messages, photos, contacts, analytics,
  crash logs, or purchase history. No ads SDK, no analytics SDK.

**Financial features, health, news, government, COVID-19:** none / not applicable.

## Testing tracks

- **Internal testing**: up to 100 testers by email, available within minutes, no review.
  Use it to check the build on real phones right away.
- **Closed testing**: needed before production on personal developer accounts created
  after 13 Nov 2023: at least **12 testers opted in for 14 days in a row**. It goes
  through review, so the listing and App content above must be complete. Start it as
  soon as possible; the 14 days only count once 12 testers are in.

Upload the same `.aab` to both. Every new upload needs a higher `version/code` in
the Android export preset (2 = the first Play build).
