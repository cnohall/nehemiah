# Translations

One gettext file per language; the English text is the key, so a missing or empty
line falls back to English in the game.

| File       | Language              | Status                                   |
|------------|-----------------------|------------------------------------------|
| `es.po`    | Spanish (Latin America) | draft, needs a native speaker's review |
| `pt_BR.po` | Portuguese (Brazil)   | draft, needs a native speaker's review   |
| `de.po`    | German                | draft, needs a native speaker's review   |
| `ko.po`    | Korean                | draft, needs a native speaker's review   |

`messages.pot` is the template for a new language (`python tools/i18n/i18n.py pot`
rewrites it). Open any of these in Poedit, or a plain text editor.

## Rules for translators

- Keep every `%s`, `%d`, `%02d` and `{name}` placeholder, **in the same order** as the
  English. Reword the sentence around them if the grammar wants another order.
- Two spaces or ` · ` split a line into separate pieces on the in-world tags and in
  the HUD. Keep them where the English has them, and don't add new ones.
- Material names come twice: capitalised for tags (`Stone`) and lower case for use
  inside a sentence (`Next: bring %s to the wall` → `stone`).
- Scripture lines are translated from the World English Bible (public domain), and
  the credits say so. If you would rather quote a public-domain Bible in your
  language, say which one and use its exact wording.
- Keep it short where the English is short: buttons, keycaps and tag labels have
  little room.

## After editing

    python tools/i18n/i18n.py check

lists missing lines and broken placeholders. New Korean text may use a syllable the
bundled font subset lacks; the check in `tools/i18n/subset_kr_font.py` prints any, and
rerunning it rebuilds `assets/fonts/NotoSerifKR/`.

To see a language in the game: Settings → Language, or
`Godot --path . --script res://tools/lang_shots.gd -- <out_dir> --lang=ko` for
screenshots of the settings, section map and a story card.
