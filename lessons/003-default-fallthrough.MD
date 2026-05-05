# Lesson 003: Default Fallthrough Was Already Boring Enough

Source: rhencke/confusio#370, from the REST default fallthrough refactor for issue #359.

## What Happened

The REST default fallthrough refactor tried to move catalog-side default handling into a
`__index` chain on the backend handler table. The intended shape was tidy: backend
overrides would win, and missing handlers would fall through to catalog-derived defaults
without a dispatch branch.

In practice, the change spread across the catalog, router, app initialization, backend
context notes, lint globals, and focused tests. The dispatch branch got smaller, but the
overall system gained a second way to explain where a handler came from.

## The Lesson

Do not hide a small explicit fallback behind table magic unless it removes enough code and
concept load to pay for the indirection. A metatable lookup can be elegant, but it also
makes provenance less local: now a missing backend key may mean "not implemented" or
"implemented by a distant default table."

Prefer the explicit fallback when it keeps route metadata, default behavior, and 404
behavior visible at the dispatch point. That is the boring path, and sometimes boring is
the maintainable choice.

## How To Use This

Before replacing fallback logic with inheritance-style lookup:

- Count every new place that must know about the lookup chain.
- Check whether debugging a missing handler becomes easier or harder.
- Keep the explicit branch if it makes default-vs-404 behavior obvious.
- Back out the refactor if the main win is a smaller dispatch function but the whole
  branch is larger or harder to explain.

The good outcome is not "dispatch has no branch." The good outcome is "a reader can tell
why this request gets this handler."
