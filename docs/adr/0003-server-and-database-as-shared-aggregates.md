# Servers and Databases are shared aggregates, referenced by ID — not owned by an Environment

> Status: accepted

In our test setup a single machine often hosts Components from several Environments, and a database is
not necessarily dedicated to one Environment ("not strict"). Because they are shared across
aggregates, `Server` and `Database` cannot live *inside* the `Environment` aggregate — that would let
deleting one Environment orphan or destroy a resource another Environment still uses. They are their
own aggregates with independent lifecycle, and Components reference them **by ID**. This is the
opposite of the legacy flat `TENVINFO` row (which baked one web-server string and exactly two DB
slots into each Environment), so it is worth recording why the ownership was deliberately inverted. A
bonus: "which Environments run on machine X / use database Y?" becomes a first-class lookup.

For identity purposes, a `Database` inventory record represents a **role-specific access profile**,
not only a physical endpoint. Its role and login profile are part of the identity alongside engine,
host, port, and service. The same physical endpoint may therefore have separate IDs when it is used as
both a business and intermediate database (or through distinct login profiles). Sharing and import
deduplication apply within the same role/access profile; this keeps role-dependent behavior such as
business-database version collection deterministic.
