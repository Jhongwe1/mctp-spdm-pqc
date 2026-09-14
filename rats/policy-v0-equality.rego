# rats/policy-v0-equality.rego — the appraisal policy AS IT WAS, frozen.
#
# Evaluated by Open Policy Agent:
#
#     opa eval --format json -i opa.input -d rats/policy-v0-equality.rego "data.spdm.output"
#
# and by rats/appraise.py, which is the same call with the exit code attached.
#
# ── Rego v1 ─────────────────────────────────────────────────────────────────
#
# This is v1 syntax: `if` before a rule body, `contains` for partial sets. OPA
# made v1 the default in 1.0 and this project measured what that costs a policy
# written before it — DMTF's SpdmSamplePolicy.rego, shipped in spdm-emu and
# documented in its readme with a bare `opa eval`, produces **eleven
# rego_parse_error** messages on OPA 1.20.2 and evaluates only under
# `--v0-compatible`. Its readme does not mention a version. See
# docs/rats-pipeline.md.
#
# ── What this policy does that DMTF's sample does not ───────────────────────
#
# The sample is 40 lines and this is longer, so the difference is worth stating
# before the code rather than after it. The sample collects evidence digests
# into a SET and reference digests into a SET and compares the two sets:
#
#     ev_hash_list[hash]  { evidence := evidence_arr[_]; hash := evidence.evidence.digest[1] }
#     SPDM_HASH_CHECK     { ev_hash_list == ref_hash_list }
#
# Three consequences, all of them demonstrated rather than argued in
# rats/rats_selftest.py, which runs the same inputs through both policies:
#
#   1. **The index is never bound to its value.** Measurement index 1 holds the
#      immutable ROM digest and index 2 holds the mutable firmware digest. Swap
#      them and the set is unchanged, so the sample passes a device whose
#      firmware digest is being presented as its ROM digest. This policy keys
#      every comparison by index, which the CoMID already carries —
#      comid_class.comid_index — and which the sample reads and discards.
#
#   2. **Duplicates collapse.** Two blocks with the same digest are one set
#      member, so a reference naming two indices is satisfied by evidence
#      naming one.
#
#   3. **An empty reference passes.** `set() == set()` is true, so a reference
#      value carrying no measurements at all appraises every device as good.
#      That is the failure direction that matters: a verifier that cannot fail
#      is indistinguishable from no verifier, and it fails OPEN.
#
#   4. **The digest algorithm is carried and never compared.** Evidence says
#      `[8, "<hex>"]` and the reference says `["sha512", "<hex>"]`; both sides
#      take element [1] and neither looks at [0]. This policy normalises the
#      algorithm identifier and requires it to agree, so a SHA-384 digest can
#      never satisfy a SHA-512 reference value by coincidence of hex.
#
# None of this makes the sample wrong for what it is — a demonstration that the
# three tools connect. It makes it the wrong thing to ship a verdict from.
#
# ── FROZEN ─────────────────────────────────────────────────────────────────
#
# ★ This file is not the live policy. It is the state rats/policy.rego was in
# before 2026-09-14, kept so that the change made that day can be MEASURED:
# the same four captures are appraised under both files and the resulting 2x4
# table is what says the new rule behaves differently, and differently in
# exactly one cell. bash rats/test_svn_policy.sh produces it.
#
# It is referenced by that script and by rats/rats_selftest.py, and by nothing
# that ships a verdict. Do not edit it to keep up with the live policy; see the
# SVN-RULE region below.
#
# Why this file exists rather than `git show`, what it costs, and the criterion
# for doing it again — freeze a RELAXATION, not a tightening:
# docs/decisions/0008-a-superseded-judgement-is-kept-as-a-control.md
#
# ── Failing closed ─────────────────────────────────────────────────────────
#
# Every check begins `default X := false` and every rule body that could be
# undefined is arranged so that undefined means false. An evidence document
# with no `evidences` key, a reference whose path does not exist, a measurement
# whose algorithm identifier is not in the table below: all of them make the
# corresponding check false rather than absent. A policy whose failure mode is
# "the rule was undefined so nothing was reported" is the one that says PASS
# on the day something unexpected arrives.

package spdm

# The evidence side and the reference side, defaulted so that a malformed or
# missing document is an empty list rather than an evaluation error. This is
# the one place where being permissive is correct: an empty evidence list with
# a non-empty reference fails `hash_check` below, which is the answer wanted.
default evidence_arr := []

evidence_arr := input.evidence.evidences

default reference_arr := []

reference_arr := input.reference.corim.unsigned_corim_map.corim_tags[0].comid_triples.comid_reference_triples

# DSP0274 negotiates a measurement hash algorithm and CoRIM names one; they are
# the same algorithms under two spellings. rats/appraise.py reads the SPDM side
# out of the ALGORITHMS response rather than taking it from a flag.
hash_alg_name := {1: "sha256", 7: "sha384", 8: "sha512"}

# ── index -> value, on both sides ──────────────────────────────────────────
#
# A duplicate index on either side is an object-rule conflict and OPA reports
# it as an evaluation error rather than picking one. That is the behaviour
# wanted: two different values claimed for one measurement index is a document
# nobody should be appraising, and rats/appraise.py turns an OPA error into
# exit code 2 — "could not tell" — rather than into a verdict.

ev_digest[idx] := [alg, value] if {
	some e in evidence_arr
	idx := e.evidence.index
	alg := hash_alg_name[e.evidence.digest[0]]
	value := e.evidence.digest[1]
}

ev_svn[idx] := svn if {
	some e in evidence_arr
	idx := e.evidence.index
	svn := e.evidence.svn
}

ref_digest[idx] := [alg, value] if {
	some triple in reference_arr
	idx := triple[0].comid_class.comid_index
	alg := triple[1].comid_mval.comid_digests[0][0]
	value := triple[1].comid_mval.comid_digests[0][1]
}

ref_svn[idx] := svn if {
	some triple in reference_arr
	idx := triple[0].comid_class.comid_index
	svn := triple[1].comid_mval.comid_svn
}

# ── what went wrong, by index, so a verdict can be explained ───────────────

digest_mismatch contains idx if {
	some idx, want in ref_digest
	ev_digest[idx] != want
}

digest_missing contains idx if {
	some idx, _ in ref_digest
	not ev_digest[idx]
}

digest_unexpected contains idx if {
	some idx, _ in ev_digest
	not ref_digest[idx]
}

# ── the checks ────────────────────────────────────────────────────────────

# A reference value that describes nothing cannot appraise anything. Named as
# its own check rather than folded into the others, because "the device is
# bad" and "nobody ever said what good looks like" are different answers and a
# verdict that cannot tell them apart is the sample policy's failure.
default reference_present := false

reference_present if {
	count(ref_digest) + count(ref_svn) > 0
}

default hash_check := false

hash_check if {
	count(ref_digest) > 0
	count(digest_mismatch) == 0
	count(digest_missing) == 0
	count(digest_unexpected) == 0
}

# >>> SVN-RULE ─────────────────────────────────────────────────────────────
#
# ★ THIS FILE IS FROZEN. It is the "before" of week 7's policy change and it
# exists for one purpose: to be run against the same four captures as
# rats/policy.rego, so that "the new rule behaves differently" is a measured
# 2x4 table rather than a claim. Do not fix, extend or tidy it. If the live
# policy grows a check outside the region markers, rats/rats_selftest.py turns
# red and the right response is to decide deliberately what the control should
# be — not to edit this file into agreement.
#
# What it does: the secure version number is compared for EQUALITY, which is
# what DMTF's SpdmSamplePolicy.rego does. Its consequence is the reason it was
# replaced, and the reason is visible in the table: an UPGRADED device (svn9)
# and a DOWNGRADED one (svn5) are refused by the same check, with the same
# message and the same exit code.

svn_mismatch contains idx if {
	some idx, want in ref_svn
	ev_svn[idx] != want
}

svn_missing contains idx if {
	some idx, _ in ref_svn
	not ev_svn[idx]
}

svn_unexpected contains idx if {
	some idx, _ in ev_svn
	not ref_svn[idx]
}

default svn_check := false

svn_check if {
	count(ref_svn) > 0
	count(svn_mismatch) == 0
	count(svn_missing) == 0
	count(svn_unexpected) == 0
}

svn_detail := {
	"svn_mismatch": svn_mismatch,
	"svn_missing_from_evidence": svn_missing,
	"svn_not_in_reference": svn_unexpected,
}

# <<< SVN-RULE ─────────────────────────────────────────────────────────────

failed_checks contains "REFERENCE_PRESENT" if not reference_present

failed_checks contains "SPDM_HASH_CHECK" if not hash_check

failed_checks contains "SPDM_SVN_CHECK" if not svn_check

default verdict := "fail"

verdict := "pass" if {
	reference_present
	hash_check
	svn_check
}

# error_code keeps the sample's shape — 0 good, 1 bad — so that a reader who
# knows SpdmSamplePolicy.rego can find their footing. verdict is the field to
# read; this one exists for continuity, not for decisions.
default error_code := 1

error_code := 0 if verdict == "pass"

output := {
	"verdict": verdict,
	"error_code": error_code,
	"checks": {
		"REFERENCE_PRESENT": reference_present,
		"SPDM_HASH_CHECK": hash_check,
		"SPDM_SVN_CHECK": svn_check,
	},
	"failed_checks": failed_checks,
	"counts": {
		"evidence_digests": count(ev_digest),
		"evidence_svns": count(ev_svn),
		"reference_digests": count(ref_digest),
		"reference_svns": count(ref_svn),
	},
	"detail": object.union(
		{
			"digest_mismatch": digest_mismatch,
			"digest_missing_from_evidence": digest_missing,
			"digest_not_in_reference": digest_unexpected,
		},
		svn_detail,
	),
}
