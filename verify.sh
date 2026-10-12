#!/usr/bin/env bash
# verify.sh: regression for the AutoDV formal labs.
#
# Runs every starter and solution configuration, plus every experiment the
# handouts describe (injected bugs, removed invariants, alternative engines),
# and compares each result with the expected one. Use it after a tool upgrade.
#
#   ./verify.sh STARTER_DIR [SOLUTION_DIR]      (solution dir defaults to this script's dir)
#   ./verify.sh path/to/labs                    a git clone: its starter-v1 tag is used
#   VERBOSE=1 ./verify.sh ...                   also print failing property names and steps
#
# Work happens in a temporary directory; the lab folders are not modified.
set -uo pipefail

STARTER=$(readlink -f "${1:?usage: verify.sh STARTER_DIR [SOLUTION_DIR]}")
SOLUTION=$(readlink -f "${2:-$(dirname "$0")}")
# The OSS CAD Suite's bin directory must be on PATH.
for tool in yosys sby eqy; do
  command -v "$tool" > /dev/null || { echo "verify.sh: $tool not found on PATH (install the OSS CAD Suite)"; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A starter clone holds your answers once you start working. If it has the
# starter-v1 tag, check that pristine snapshot instead of the working tree.
if git -C "$STARTER" rev-parse -q --verify refs/tags/starter-v1 > /dev/null 2>&1; then
  mkdir -p "$WORK/starter"
  git -C "$STARTER" archive starter-v1 | tar -x -C "$WORK/starter"
  STARTER="$WORK/starter"
  echo "(starter: tag starter-v1)"
fi
pass=0
fail=0

# check NAME EXPECTED ACTUAL [DETAIL]
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf '  ok    %-58s %s\n' "$1" "$3"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-58s expected %s, got %s\n' "$1" "$2" "$3"
  fi
  if [ -n "${VERBOSE:-}" ] && [ -n "${4:-}" ]; then printf '        %s\n' "$4"; fi
}

# copy LAB SRC: fresh copy of a lab folder into $WORK/run
copy() {
  rm -rf "$WORK/run"
  cp -r "$2/$1" "$WORK/run"
}

# sby_status SBYFILE TASK [EXTRA_ARGS]: run one task, echo its status word
sby_status() {
  (cd "$WORK/run" && sby -f "$1" "$2" > /dev/null 2>&1)
  awk '{print $1}' "$WORK/run/${1%.sby}_$2/status" 2>/dev/null || echo ERROR
}

# first_fail SBYFILE TASK: "<property> step N" of the first reported failure
first_fail() {
  grep -ohE 'failed assertion [^ ]+ at [^ ]+ step [0-9]+' "$WORK/run/${1%.sby}_$2/logfile.txt" 2>/dev/null |
    sed -E 's/failed assertion [^.]+\.//; s/ at [^ ]+ / /' | sort -t' ' -k3n | head -1
}

# eqy_status EQYFILE: status word of an EQY run
eqy_status() {
  (cd "$WORK/run" && eqy -f "$1" > eqy.log 2>&1)
  grep -oE 'DONE \([A-Z]+' "$WORK/run/eqy.log" | tail -1 | sed 's/DONE (//'
}

eqy_failed_parts() {
  grep -oE 'Failed to prove equivalence of partition [^ ]+' "$WORK/run/eqy.log" | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# =============================================================================
echo "Lab 1: saturating up/down counter"
copy lab-1 "$STARTER"
check "starter bmc finds the planted bug"            FAIL "$(sby_status updown_counter.sby bmc)"
check "starter bmc: property and step"               "a_count_le_max step 11" "$(first_fail updown_counter.sby bmc)"
copy lab-1 "$SOLUTION"
for t in bmc cover prove; do check "solution $t" PASS "$(sby_status updown_counter.sby $t)"; done
copy lab-1 "$SOLUTION"
sed -i 's|^  always_comb if (!f_past_valid) m_reset_first: assume (rst);|&\n  always_comb m_no_inc: assume (!inc);|' "$WORK/run/fv_updown_counter.sv"
check "over-constrained (assume !inc): bmc still passes" PASS "$(sby_status updown_counter.sby bmc)"
check "over-constrained (assume !inc): covers unreachable" FAIL "$(sby_status updown_counter.sby cover)"
copy lab-1 "$STARTER"
check "starter prove on the buggy design"            FAIL "$(sby_status updown_counter.sby prove)"
mut1() { # NAME SED_EXPR EXPECTED_FIRST_FAIL
  copy lab-1 "$SOLUTION"; sed -i "$2" "$WORK/run/updown_counter.sv"
  check "mutation $1" "FAIL $3" "$(sby_status updown_counter.sby bmc) $(first_fail updown_counter.sby bmc)"
}
mut1 "M1 increments past MAX"  's/count != MAX) begin/count <= MAX) begin/'                     "a_count_le_max step 11"
mut1 "M2 decrements below 0"   "s/dec \&\& !inc \&\& count != '0/dec \&\& !inc/"                "a_count_le_max step 2"
mut1 "M3 inc+dec decrements"   's/dec \&\& !inc \&\& count/dec \&\& count/'                     "a_hold step 4"
mut1 "M4 at_min wrong"         "s/assign at_min = (count == '0);/assign at_min = (count <= 4'd1);/" "a_at_min step 2"

# =============================================================================
echo "Lab 2: synchronous FIFO"
copy lab-2 "$STARTER"
check "starter bmc"                                  PASS    "$(sby_status sync_fifo.sby bmc)"
check "starter prove (induction fails)"              UNKNOWN "$(sby_status sync_fifo.sby prove)"
sed -i 's/^prove: depth 20/prove: depth 40/' "$WORK/run/sync_fifo.sby"
check "starter prove at depth 40 (still fails)"      UNKNOWN "$(sby_status sync_fifo.sby prove)"
copy lab-2 "$SOLUTION"
for t in bmc prove cover; do check "solution $t" PASS "$(sby_status sync_fifo.sby $t)"; done
copy lab-2 "$SOLUTION"
sed -i '/a_in_fifo_iff: assert/d; /a_mem_holds: assert/d' "$WORK/run/fv_sync_fifo.sv"
check "solution without Task 5 invariants: prove"    UNKNOWN "$(sby_status sync_fifo.sby prove)"
mut2() {
  copy lab-2 "$SOLUTION"; sed -i "$2" "$WORK/run/sync_fifo.sv"
  check "mutation $1" "FAIL $3" "$(sby_status sync_fifo.sby bmc) $(first_fail sync_fifo.sby bmc)"
}
mut2 "F1 full ignores wrap bit"        's/assign full  = (wr_ptr\[AW\] != rd_ptr\[AW\]) \&\& /assign full  = /'   "a_full step 1"
mut2 "F2 read while empty"             's/assign do_read  = rd_en \&\& !empty;/assign do_read  = rd_en;/'        "a_in_fifo_iff step 2"
mut2 "F3 rdata off by one"             "s/assign rdata = mem\[rd_ptr\[AW-1:0\]\];/assign rdata = mem[rd_ptr[AW-1:0] + 1'b1];/" "a_data step 2"
mut2 "F4 write ignores full"           's/assign do_write = wr_en \&\& !full;/assign do_write = wr_en;/'         "a_in_fifo_iff step 6"
mut2 "F5 level misses simultaneous r/w" "s/level <= level + (AW+1)'(do_write) - (AW+1)'(do_read);/level <= do_write ? level + 1'b1 : (do_read ? level - 1'b1 : level);/" "a_level_ptrs step 3"

# =============================================================================
echo "Lab 3: round-robin arbiter"
copy lab-3 "$STARTER"
for t in bmc prove cover; do check "starter $t (buggy RTL, safety only)" PASS "$(sby_status rr_arbiter.sby $t)"; done
copy lab-3 "$SOLUTION"
for t in bmc prove cover; do check "solution $t" PASS "$(sby_status rr_arbiter.sby $t)"; done
copy lab-3 "$SOLUTION"; cp "$STARTER/lab-3/rr_arbiter.sv" "$WORK/run/"
check "E1 solution properties on buggy RTL"          "FAIL g_req[1].a_bounded_wait step 5" "$(sby_status rr_arbiter.sby bmc) $(first_fail rr_arbiter.sby bmc | tr -d '\\')"
copy lab-3 "$SOLUTION"; cp "$STARTER/lab-3/rr_arbiter.sv" "$WORK/run/"
sed -i 's|^  // Task 1: grants go only|  always_comb m_one_req: assume ($onehot0(req));\n  // Task 1: grants go only|' "$WORK/run/fv_rr_arbiter.sv"
check "E2 buggy RTL + one-request assumption: bmc"   PASS "$(sby_status rr_arbiter.sby bmc)"
check "E2 buggy RTL + one-request assumption: cover" FAIL "$(sby_status rr_arbiter.sby cover)"
copy lab-3 "$SOLUTION"; sed -i 's/m_hold: assume (req\[i\]);/;/' "$WORK/run/fv_rr_arbiter.sv"
check "E3 without the hold assumption: prove"        PASS "$(sby_status rr_arbiter.sby prove)"
copy lab-3 "$SOLUTION"; sed -i 's/a_bounded_wait: assert (wait_cnt < N);/a_bounded_wait: assert (wait_cnt < N - 1);/' "$WORK/run/fv_rr_arbiter.sv"
check "E4 bound N-1 is too tight"                    "FAIL g_req[3].a_bounded_wait step 4" "$(sby_status rr_arbiter.sby bmc) $(first_fail rr_arbiter.sby bmc | tr -d '\\')"

# =============================================================================
echo "Lab 4: valid/ready skid buffer"
copy lab-4 "$STARTER"
for t in bmc prove cover; do check "starter $t (buggy RTL, handshake only)" PASS "$(sby_status skid_buffer.sby $t)"; done
copy lab-4 "$SOLUTION"
for t in bmc prove cover pdr ric3 suprove; do check "solution $t" PASS "$(sby_status skid_buffer.sby $t)"; done
copy lab-4 "$SOLUTION"; cp "$STARTER/lab-4/skid_buffer.sv" "$WORK/run/"
check "solution properties on buggy RTL"             "FAIL a_occ_regs step 4" "$(sby_status skid_buffer.sby bmc) $(first_fail skid_buffer.sby bmc)"
copy lab-4 "$SOLUTION"; sed -i '/a_track_m:    assert/d; /a_track_skid: assert/d' "$WORK/run/fv_skid_buffer.sv"
check "without Task 4 invariants: k-induction"       UNKNOWN "$(sby_status skid_buffer.sby prove)"
for t in pdr ric3 suprove; do check "without Task 4 invariants: $t" PASS "$(sby_status skid_buffer.sby $t)"; done
echo "  timing (solution, prove tasks, seconds):"
for w in 1 8 32; do
  copy lab-4 "$SOLUTION"; sed -i "s/-G WIDTH=8/-G WIDTH=$w/" "$WORK/run/skid_buffer.sby"
  line="    WIDTH=$w"
  for t in prove pdr ric3 suprove; do
    s=$(date +%s.%N); st=$(sby_status skid_buffer.sby $t)
    line="$line  $t=$st $(printf '%.1f' "$(echo "$(date +%s.%N) - $s" | bc)")"
  done
  echo "$line"
done

# =============================================================================
echo "Lab 5: RTL vs refactored RTL (EQY)"
copy lab-5 "$SOLUTION"
check "solution eqy"                                 PASS "$(eqy_status bitops.eqy)"
check "solution partitions"                          5    "$(wc -l < "$WORK/run/bitops/partition.list")"
copy lab-5 "$SOLUTION"
sed -i "s/assign p4\[i\] = {1'b0, p2\[2\*i\]} + {1'b0, p2\[2\*i+1\]};/assign p4[i] = {1'b0, p2[2*i]} + {1'b0, p2[2*i]};/" "$WORK/run/bitops_gate.sv"
check "X1 adder-tree bug"                            "FAIL bitops.pop_d" "$(eqy_status bitops.eqy) $(eqy_failed_parts)"
copy lab-5 "$SOLUTION"; sed -i 's/lzc_d/lzc_next/g' "$WORK/run/bitops_gate.sv"
check "X2 renamed lzc_d"                             "PASS 4" "$(eqy_status bitops.eqy) $(wc -l < "$WORK/run/bitops/partition.list")"
copy lab-5 "$SOLUTION"
sed -i "s/assign lzc_d = (din == 16'h0000) ? 5'd16 : {1'b0, z8, z4, z2, z1};/assign lzc_d = {1'b0, z8, z4, z2, z1};/; s/        lzc <= lzc_d;/        lzc <= (din == 16'h0000) ? 5'd16 : lzc_d;/" "$WORK/run/bitops_gate.sv"
check "X3 same name, different meaning"              "FAIL bitops.lzc bitops.lzc_d" "$(eqy_status bitops.eqy) $(eqy_failed_parts)"
printf '\n[match bitops]\ngold-nomatch lzc_d\n' >> "$WORK/run/bitops.eqy"
check "X3 with gold-nomatch lzc_d"                   PASS "$(eqy_status bitops.eqy)"
copy lab-5 "$SOLUTION"
(cd "$WORK/run" && yosys -m slang -s miter.ys > miter.log 2>&1); check "miter.ys proves equivalence" 0 "$?"
sed -i "s/assign p4\[i\] = {1'b0, p2\[2\*i\]} + {1'b0, p2\[2\*i+1\]};/assign p4[i] = {1'b0, p2[2*i]} + {1'b0, p2[2*i]};/" "$WORK/run/bitops_gate.sv"
(cd "$WORK/run" && yosys -m slang -s miter.ys > miter.log 2>&1); check "miter.ys catches the adder-tree bug" 1 "$?"

# =============================================================================
echo "Lab 6: RTL vs synthesized netlist"
copy lab-6 "$SOLUTION"
(cd "$WORK/run" && yosys -m slang -s synth.ys > synth.log 2>&1 && yosys -m slang -s synth_fsm.ys > synth_fsm.log 2>&1)
check "netlists written" "yes" "$([ -s "$WORK/run/tl_ctrl_netlist.v" ] && [ -s "$WORK/run/tl_ctrl_netlist_fsm.v" ] && echo yes || echo no)"
check "-nofsm netlist keeps state register"          1 "$(grep -c 'reg \[1:0\] state;' "$WORK/run/tl_ctrl_netlist.v")"
check "FSM netlist has no state register"            0 "$(grep -c 'reg \[1:0\] state;' "$WORK/run/tl_ctrl_netlist_fsm.v")"
check "solution eqy (grouped)"                       PASS "$(eqy_status tl_ctrl.eqy)"
cp "$WORK/run/tl_ctrl.eqy" "$WORK/grouped.eqy"
sed -i '/^\[collect \*\]/,/^group /d' "$WORK/run/tl_ctrl.eqy"
check "without grouping: false failures"             "FAIL tl_ctrl.state tl_ctrl.timer" "$(eqy_status tl_ctrl.eqy) $(eqy_failed_parts)"
cp "$WORK/grouped.eqy" "$WORK/run/tl_ctrl.eqy"; sed -i 's/read_verilog tl_ctrl_netlist.v/read_verilog tl_ctrl_netlist_fsm.v/' "$WORK/run/tl_ctrl.eqy"
check "FSM-optimized netlist (grouped)"              PASS "$(eqy_status tl_ctrl.eqy)"
cp "$WORK/grouped.eqy" "$WORK/run/tl_ctrl.eqy"
(cd "$WORK/run" && yosys -m slang -s equiv.ys > equiv.log 2>&1); check "equiv.ys on the -nofsm netlist" 0 "$?"
first_and=$(grep -m1 -nE '^  assign _[0-9]+_ = ~timer\[0\];' "$WORK/run/tl_ctrl_netlist.v" | cut -d: -f1)
if [ -n "$first_and" ]; then
  sed -i "${first_and}s/= ~timer\[0\];/= timer[0];/" "$WORK/run/tl_ctrl_netlist.v"
  check "netlist bug (inverter removed): eqy"        FAIL "$(eqy_status tl_ctrl.eqy)"
  (cd "$WORK/run" && yosys -m slang -s equiv.ys > equiv.log 2>&1); check "netlist bug: equiv.ys" 1 "$?"
else
  check "netlist bug site found" yes no
fi

echo
echo "verify.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
