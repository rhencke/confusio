# Lesson 004: Transport Layers Did Not Pay For The Stack

Source: rhencke/confusio#371, from the HTTP transport metatable-layer refactor for issue #360.

## What Happened

The transport refactor tried to replace `make_backend_transport` with explicit metatable
layers for base fetch behavior, auth, pagination, and error-shape mapping. The intended
shape was flexible: backends would compose only the layers they needed, and a future layer
such as retry-on-5xx could be added in one place.

In practice, the change added more surface area than it removed. The backend setup lines
became more explicit, but the transport module gained layer machinery, new helper closures,
extra tests, doc churn, and another concept every backend reader had to understand.

## The Lesson

A more decomposable design is not automatically a simpler design. If every current backend
uses nearly the same stack, a small factory can be clearer than a set of formally separate
layers.

Prefer explicit composition when it removes real variation or makes new behavior local
without making the common case harder to read. If the flexibility is mostly hypothetical,
keep the boring helper and write down the lesson instead.

## How To Use This

Before replacing a compact factory with composable layers:

- Count the setup noise at every call site, not only the helper body.
- Check whether current backends actually vary enough to need independent layers.
- Treat future extension points as a cost unless there is an immediate user.
- Back out the refactor if the main win is theoretical flexibility and the branch gets
  larger or harder to explain.

The good outcome is not "the design can express every possible layer." The good outcome is
"the transport path is obvious for the backends that exist today."
