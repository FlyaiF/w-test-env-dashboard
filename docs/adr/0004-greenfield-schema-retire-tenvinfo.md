# Discard the TENVINFO schema; build a greenfield normalized schema with a one-time import

> Status: accepted

The legacy `TENVINFO` table is too weak for the new model: it crams composite concepts into single
columns (`E_WEBSERVERADDR` = `"host:port&user/password"`), hard-codes cardinality (exactly two DB
slots, one log path, one version), and even contradicts itself (one version column, but per-subsystem
versions collected from the business DB). `TENVINFO` is ours alone to reshape, so rather than keep a
compatibility view we discard the schema and design a fresh normalized schema for the
Environment/Component/Server/Database model. Migration is a **one-time scripted import** run once the
new schema is ready — parsing the composite strings and fixed slots into proper rows — which doubles
as proof the new model can represent reality. Backend cutover is necessarily big-bang (Go→Java,
new schema); the new backend runs in parallel until validated, then the old setup is retired.
