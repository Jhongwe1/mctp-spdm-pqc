# certs

Self-signed three-layer certificate chain (root -> intermediate -> leaf) and the
scripts that generate it, plus the `openssl x509 -text` output for each layer.

Arrives in **G2 (weeks 3-5)**. Generating a chain the responder will actually
accept is the prerequisite for tampering with it in a controlled way.

Nothing here is secret. The private keys are generated locally, are for an
emulator, and protect nothing — but `.gitignore` excludes `*.key` anyway,
because a habit that only applies to important keys is not a habit.
