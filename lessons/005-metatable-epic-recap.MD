# Lesson 005: The Epic Has To Pay Too

Source: rhencke/confusio#372, from the metatable-shrink epic for issue #356.

## What Happened

The metatable-shrink epic started with a plausible pattern: several parts of
confusio looked hand-rolled in ways Lua metatables might simplify. Translators
could become callable data, aliases could inherit through `__index`, defaults
could fall through through the backend handler table, and transport could stack
as layers.

Each experiment was tried on its own PR. Each one either grew the branch or made
the behavior harder to explain, so the production code was backed out and the
useful result became the lessons in this directory.

## The Lesson

An epic made of individually questionable refactors does not become good because
the theme is coherent. The whole proposal has to pay rent too.

Metatables are powerful, but power is not the same thing as simplification. Use
them when they make a real invariant smaller, more local, or easier to verify.
Do not use them just because several code paths can be described as lookup,
fallback, wrapping, or inheritance.

## How To Use This

Before committing to a broad architectural theme:

- Land the smallest representative slice first and measure the whole branch.
- Treat review feedback on one slice as evidence about the whole epic.
- Stop early when the repeated result is more plumbing, more docs, or worse
  debuggability.
- Preserve the lesson when the experiment teaches something useful, even if the
  code is not worth keeping.

The good outcome is not "the epic shipped." The good outcome is "the codebase
kept what helped and remembered what did not."
