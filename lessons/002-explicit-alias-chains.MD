# Lesson 002: Explicit Alias Chains Still Have To Pay

Source: rhencke/confusio#369, from the Gitea-family alias backend refactor for issue #358.

## What Happened

The alias backend refactor tried to replace Gitea-family `dofile` loading with explicit
`__index` chains. The intent was good: make the alias relationship machine-readable, keep
the backend diffs local, and avoid hiding inheritance in load order.

Once all four aliases moved over, the PR had grown instead of shrinking. The explicit chain
needed reusable backend specs, loader support, validator changes, test coverage, and updated
docs. The result explained the relationship better, but made the codebase heavier.

## The Lesson

Explicit structure is not automatically simpler. If exposing a relationship requires new
plumbing in several layers, compare that cost against the boring mechanism already in place.

A refactor earns its keep when it reduces future work, narrows the number of concepts a
reader needs, or removes a real source of bugs. If it mostly turns an implicit convention
into a formal mechanism, measure the whole branch before keeping it.

## How To Use This

Before replacing a small convention with a reusable framework:

- Count every support change, not just the target files.
- Check whether validators, loaders, docs, and tests become simpler or more complex.
- Prefer a clear comment and a small convention when the formal model needs broad plumbing.
- Back out the refactor if the main outcome is "more explicit" but not "easier to maintain."

The good outcome is not "every relationship is encoded in a reusable abstraction." The good
outcome is "the next person can change this safely with less code in their head."
