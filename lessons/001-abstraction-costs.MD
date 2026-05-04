# Lesson 001: Abstractions Must Pay Rent

Source: rhencke/confusio#368, from the translators-as-data refactor for issue #357.

## What Happened

The translators-as-data refactor started with a good smell: hundreds of backend translator functions repeated the same field-copying shape. A shared callable translator engine looked like it should collapse that repetition into smaller data specs.

After the broad migration, the PR was still roughly 2,000 lines larger than the original branch. A PR-wide audit showed the abstraction was not the whole answer: some conversions were smaller and clearer, but many backend migrations replaced obvious handwritten helpers with a mini-language plus enough spec shape to make the code larger and harder to judge.

## The Lesson

An abstraction has to pay for itself in clarity, maintenance cost, and reviewability. A nominal LOC win is not enough, and a tiny net shrink definitely does not justify a new language in the codebase.

Prefer narrowing an abstraction to the cases where it is plainly better. If the general version only works after adding helpers, transforms, grouping rules, and special cases, stop and compare it against the boring code it replaces.

## How To Use This

Before landing a broad deduplication refactor:

- Measure the whole PR against `origin/main`, not only the files that motivated the work.
- Separate the cases where the abstraction clearly improves the code from the cases where it only moves complexity around.
- Keep the abstraction if it makes those cases easier to read, test, and extend.
- Back out or leave alone the cases where the original code is simpler.

The good outcome is not "all similar code uses the new abstraction." The good outcome is "the codebase is easier to work on after this PR."
