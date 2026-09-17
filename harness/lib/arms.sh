# shellcheck shell=bash
#
# harness/lib/arms.sh — the controlled set, and the six algorithm groups.
#
# Source this, do not execute it. It defines three things and nothing else:
#
#     COMMON=(...)        the flags that are identical in every arm
#     EXPECT_FIXED=...    what the negotiation must produce regardless of arm
#     ALGO_GROUPS=(...)   label | arm-only flags | the four groups that move
#
# Why it is its own file
# ----------------------
# It lived inside harness/run_pair.sh until 2026-09-18, which was correct while
# run_pair.sh was the only thing that ran a handshake. Week nine added a second
# one — harness/run_afmctp.sh, which runs the same arms inside a virtual
# machine so they cross a real MCTP link — and the whole point of that run is
# that it is comparable with the socket-line captures already published.
#
# Two copies of COMMON would make that comparison a claim instead of a fact:
# the two runs would differ in whatever drifted, the diff would be invisible,
# and the conclusion would be attributed to the transport. So there is one
# copy, and harness/verify_repo.sh additionally requires it to match the
# controlled_flags string recorded in the manifests of the runs already in
# bench/data/ — which is what makes the extraction checkable rather than
# merely careful.

# shellcheck disable=SC2034
# Every name below is consumed by the scripts that source this file and never
# here. SC2034 cannot see across a dot-source, and it would be right about a
# file that really did define an unused variable, so the suppression is scoped
# to this one file and stated rather than turned off globally.

# ── the controlled set ─────────────────────────────────────────────────────
#
# Eighteen flags, every one of which is identical in every arm. Anything the
# emulator negotiates or sizes a message by is in here; what is NOT in here is
# in the per-arm lists below, and that difference is the experiment.
#
# SC2054 fires on the commas inside --exe_conn's value. They are the
# emulator's own separator for a list of operations, not array syntax.
# shellcheck disable=SC2054
COMMON=(
    --ver            1.4
    --sec_ver        1.2
    --hash           SHA_384
    --meas_hash      SHA_384
    --aead           AES_256_GCM
    --other_param    OPAQUE_FMT_1
    --key_schedule   HMAC_HASH
    --meas_att       HASH
    --meas_sum       ALL
    --slot_count     1
    --slot_id        0
    --exe_conn       DIGEST,CERT,CHAL,MEAS
    --exe_session    NO_END
    # Mutual authentication off — the FLOW, which is what puts a requester
    # certificate chain on the wire. Measured, not assumed: harness/lib/
    # check_negotiated.py requires the capture to carry no encapsulated
    # exchange and zero requester chain bytes.
    --basic_mut_auth NO
    --mut_auth       NO
    # ── and the requester's OWN signature algorithm, which cannot be off ───
    #
    # plan/W07 said --req_asym NONE --req_pqc_asym NONE. That combination
    # makes the handshake impossible on this build, and the symptom is six
    # packets and `ERROR: libspdm_init_connection - 0x8001000a` with nothing
    # naming a flag. libspdm/library/spdm_responder_lib/libspdm_rsp_algorithms.c:
    #
    #     if (MUT_AUTH_CAP supported || requester advertises EP_INFO_CAP_SIG) {
    #         algo_size     = libspdm_get_req_asym_signature_size(...);
    #         pqc_algo_size = libspdm_get_req_pqc_asym_signature_size(...);
    #         if (((algo_size == 0) && (pqc_algo_size == 0)) ||
    #             ((algo_size != 0) && (pqc_algo_size != 0))) {
    #             return INVALID_REQUEST;   /* exactly one, never zero or two */
    #         }
    #     }
    #
    # --mut_auth and --basic_mut_auth are FLOW policy. They do not clear
    # MUT_AUTH_CAP or EP_INFO_CAP_SIG out of m_use_requester_capability_flags,
    # so the responder still requires the requester to name exactly one
    # signature algorithm for itself.
    #
    # So it is pinned rather than removed, to the SAME classical value in every
    # arm. Nothing signs with it — no encapsulated exchange happens — and the
    # only thing it puts on the wire is one 4-byte AlgStructure entry that is
    # byte-identical in every arm. Reported as upstream candidate 6 in
    # docs/upstream/README.md.
    --req_asym       ECDSA_P384
    --req_pqc_asym   NONE
)

# Everything the negotiation must produce that is NOT the independent variable.
# Written out rather than derived from COMMON: deriving it would compare the
# flags with themselves and pass on a capture where the responder chose
# something else entirely.
EXPECT_FIXED="Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"

# ── the six algorithm groups ───────────────────────────────────────────────
#
#   label | arm-only flags | expected negotiation for the four groups that move
ALGO_GROUPS=(
"A0|--asym ECDSA_P384 --dhe SECP_384_R1 --pqc_asym NONE --kem NONE|Asym=ECDSA_P384;DHE=SECP_384_R1;PqcAsym=;KEM="
"A1|--asym ECDSA_P521 --dhe SECP_521_R1 --pqc_asym NONE --kem NONE|Asym=ECDSA_P521;DHE=SECP_521_R1;PqcAsym=;KEM="
"P1|--asym NONE --dhe NONE --pqc_asym ML_DSA_44 --kem ML_KEM_512 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_44;KEM=ML_KEM_512"
"P2|--asym NONE --dhe NONE --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_65;KEM=ML_KEM_768"
"P3|--asym NONE --dhe NONE --pqc_asym ML_DSA_87 --kem ML_KEM_1024 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_87;KEM=ML_KEM_1024"
"S1|--asym NONE --dhe NONE --pqc_asym SLH_DSA_SHA2_128S --kem ML_KEM_512 --pqc_first TRUE|Asym=;DHE=;PqcAsym=SLH_DSA_SHA2_128S;KEM=ML_KEM_512"
)
