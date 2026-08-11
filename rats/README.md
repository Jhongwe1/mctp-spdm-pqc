# rats

The part SPDM does not standardise: reference values, the policy that compares
evidence against them, and the verdicts that come out.

Arrives in **G3 (weeks 5-7)**. See [`../docs/rats-roles.md`](../docs/rats-roles.md)
for why this directory is where the project's actual contribution lives — SPDM
covers getting the evidence, and nothing after that.

The assertion this has to support, stated as a negative because that is the
form that can fail usefully: a **tampered** measurement must be **rejected**,
and CI must turn red if it stops being.
