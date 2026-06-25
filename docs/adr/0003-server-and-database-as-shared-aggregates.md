# Servers and Databases are shared aggregates, referenced by ID — not owned by an Environment

In our test setup a single machine often hosts Components from several Environments, and a database is
not necessarily dedicated to one Environment ("not strict"). Because they are shared across
aggregates, `Server` and `Database` cannot live *inside* the `Environment` aggregate — that would let
deleting one Environment orphan or destroy a resource another Environment still uses. They are their
own aggregates with independent lifecycle, and Components reference them **by ID**. This is the
opposite of the legacy flat `TENVINFO` row (which baked one web-server string and exactly two DB
slots into each Environment), so it is worth recording why the ownership was deliberately inverted. A
bonus: "which Environments run on machine X / use database Y?" becomes a first-class lookup.
