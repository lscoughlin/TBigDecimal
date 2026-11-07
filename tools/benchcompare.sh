#!/bin/sh
# benchcompare.sh - record or compare benchmark baselines.
#
#   sh tools/benchcompare.sh write [output.csv]
#       Runs the BenchSmall, BenchAll, BenchParseFormat and BenchFinancial
#       targets (each when present), parses allocation rows from
#       BenchSmall and timing rows from the other three, and writes a CSV
#       with columns:
#       host,fpc_version,target_cpu,operation,digits,nanoseconds,allocations,bytes
#       Timing rows carry the printed median value converted to nanoseconds and
#       zero allocations/bytes. Allocation rows carry zero nanoseconds.
#       Default output: bench/baseline.csv
#
#   sh tools/benchcompare.sh merge output.csv in1.csv in2.csv [in3.csv ...]
#       Writes one row per operation/digits key: the row with the
#       smallest value (nanoseconds, or bytes when nanoseconds is 0).
#
#   sh tools/benchcompare.sh compare baseline.csv current.csv
#   sh tools/benchcompare.sh baseline.csv current.csv
#       Prints rows whose nanoseconds (or bytes, when nanoseconds are 0)
#       differ by more than 5%. Exits 1 when a row regresses by more
#       than 10%, 0 when no such regression exists, 2 on error.
set -u

mode=${1:-}

fail() { echo "benchcompare: $*" >&2; exit 2; }

case "$mode" in
  write)
    out=${2:-bench/baseline.csv}
    host=$(uname -n)
    fpcver=$(fpc -iV 2>/dev/null || echo unknown)
    cpu=$(uname -m)
    tmpd=$(mktemp -d) || fail "mktemp failed"
    trap 'rm -rf "$tmpd"' EXIT INT TERM
    run_target() {
      # $1 = make target, $2 = source file, $3 = output file
      if [ -f "$2" ]; then
        make "$1" > "$3" 2>&1 || fail "make $1 failed"
      else
        echo "benchcompare: $2 missing, skipped" >&2
        : > "$3"
      fi
    }
    run_target benchsmall bench/BenchSmall.lpr "$tmpd/small.txt"
    run_target bench bench/BenchAll.lpr "$tmpd/all.txt"
    run_target benchparse bench/BenchParseFormat.lpr "$tmpd/parse.txt"
    run_target benchfinancial bench/BenchFinancial.lpr "$tmpd/financial.txt"
    {
      echo "host,fpc_version,target_cpu,operation,digits,nanoseconds,allocations,bytes"
      awk -v host="$host" -v fpc="$fpcver" -v cpu="$cpu" '
        /allocations,/ {
          op=""; calls=""; bytes="";
          for (i=1;i<=NF;i++) {
            if ($i=="adds") op="add";
            else if ($i=="multiplies" && op=="") op="multiply";
            else if ($i=="subtracts") op="subtract";
            else if ($i=="compares") op="compare";
            else if ($i=="divides") op="divide";
            else if ($i=="sqrts") op="sqrt";
            else if ($i=="parses") op="parse";
            else if ($i=="formats") op="format";
            else if ($i=="1000-digit") op="multiply1000";
            else if ($i ~ /^calls=/) { split($i,a,"="); calls=a[2]; }
            else if ($i ~ /^bytes=/) { split($i,a,"="); bytes=a[2]; }
          }
          digits = (op=="multiply1000") ? 1000 : 9;
          if (op!="") printf "%s,%s,%s,%s,%d,0,%s,%s\n", host, fpc, cpu, op, digits, calls, bytes;
        }' "$tmpd/small.txt"
      awk -v host="$host" -v fpc="$fpcver" -v cpu="$cpu" '
        function medn(n,   i,c,v) { c=0; for(i=1;i<=NF;i++) if($i=="median"){ c++; if(c==n){ v=$(i+1); return v } } return "" }
        /^Multiplication/ { sec="mul"; next }
        /^Division/ { sec="div"; next }
        /^Factorial/ { sec="fact"; next }
        /^Binomial/ { sec="binom"; next }
        /^Functions/ { sec="func"; next }
        sec=="mul" && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9.]+$/ && $3 ~ /^[0-9.]+$/ {
          split(medn(1), a, "/");
          if (a[1]+0>0) printf "%s,%s,%s,mul-schoolbook,%d,%.0f,0,0\n", host, fpc, cpu, $1*9, a[1]*1000;
          if (a[2]+0>0) printf "%s,%s,%s,mul-karatsuba,%d,%.0f,0,0\n", host, fpc, cpu, $1*9, a[2]*1000;
          next;
        }
        sec=="div" && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9.]+$/ && $3 ~ /^[0-9.]+$/ {
          split(medn(1), a, "/");
          if (a[1]+0>0) printf "%s,%s,%s,div-knuth,%d,%.0f,0,0\n", host, fpc, cpu, $1*9, a[1]*1000;
          if (a[2]+0>0) printf "%s,%s,%s,div-newton,%d,%.0f,0,0\n", host, fpc, cpu, $1*9, a[2]*1000;
          next;
        }
        sec=="fact" && $1=="factorial" {
          r=medn(1); w=medn(2);
          if (r+0>0) printf "%s,%s,%s,factorial-range,%d,%.0f,0,0\n", host, fpc, cpu, $2, r*1000000;
          if (w+0>0) printf "%s,%s,%s,factorial-swing,%d,%.0f,0,0\n", host, fpc, cpu, $2, w*1000000;
          next;
        }
        sec=="binom" && $1=="binomial" {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,binomial-%s,%d,%.0f,0,0\n", host, fpc, cpu, $4, $3, v*1000000;
          next;
        }
        sec=="binom" && $1=="permutation" {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,permutation,%d,%.0f,0,0\n", host, fpc, cpu, $3, v*1000000;
          next;
        }
        sec=="func" && $3=="digits" {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,func-%s,%d,%.0f,0,0\n", host, fpc, cpu, $1, $2, v*1000;
          next;
        }' "$tmpd/all.txt"
      awk -v host="$host" -v fpc="$fpcver" -v cpu="$cpu" '
        function medn(n,   i,c,v) { c=0; for(i=1;i<=NF;i++) if($i=="median"){ c++; if(c==n){ v=$(i+1); return v } } return "" }
        /us\/call/ && $2 ~ /^[0-9]+$/ {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,%s:%s,%d,%.0f,0,0\n", host, fpc, cpu, $1, $3, $2, v*1000;
        }' "$tmpd/parse.txt"
      awk -v host="$host" -v fpc="$fpcver" -v cpu="$cpu" '
        function medn(n,   i,c,v) { c=0; for(i=1;i<=NF;i++) if($i=="median"){ c++; if(c==n){ v=$(i+1); return v } } return "" }
        /us\/call/ && $2 ~ /^[0-9]+$/ {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,%s:%s,%d,%.0f,0,0\n", host, fpc, cpu, $1, $3, $2, v*1000;
        }
        /us\/schedule/ && $2 ~ /^[0-9]+$/ {
          v=medn(1);
          if (v+0>0) printf "%s,%s,%s,%s:%s,%d,%.0f,0,0\n", host, fpc, cpu, $1, $3, $2, v*1000;
        }' "$tmpd/financial.txt"
    } > "$out" || fail "cannot write $out"
    echo "benchcompare: wrote $out" >&2
    ;;
  merge)
    out=${2:-}
    [ -n "$out" ] || fail "usage: benchcompare.sh merge output.csv in1.csv [in2.csv ...]"
    shift 2
    [ $# -ge 1 ] || fail "usage: benchcompare.sh merge output.csv in1.csv [in2.csv ...]"
    for f in "$@"; do [ -f "$f" ] || fail "missing file: $f"; done
    {
      echo "host,fpc_version,target_cpu,operation,digits,nanoseconds,allocations,bytes"
      awk -F, '
        FNR==1 { next }
        {
          key=$4","$5;
          val=($6>0) ? $6 : $8;
          if (val==0 && (key in best) && best[key]>0) next;
          if (!(key in best) || val < best[key]) { best[key]=val; row[key]=$0; }
        }
        END { for (k in row) print row[k]; }' "$@"
    } > "$out" || fail "cannot write $out"
    echo "benchcompare: wrote $out" >&2
    ;;
  compare|*.csv)
    if [ "$mode" = compare ]; then
      base=${2:-}; cur=${3:-}
    else
      base=${1:-}; cur=${2:-}
    fi
    [ -n "$base" ] && [ -n "$cur" ] || fail "usage: benchcompare.sh compare baseline.csv current.csv"
    [ -f "$base" ] || fail "missing file: $base"
    [ -f "$cur" ] || fail "missing file: $cur"
    awk -F, '
      NR==FNR {
        if (FNR==1) next;
        key=$4","$5; old[key]=$6; oldb[key]=$8; next;
      }
      FNR==1 { next }
      {
        key=$4","$5;
        if (!(key in old)) next;
        o=old[key]; n=$6;
        if (o==0) { o=oldb[key]; n=$8; }
        if (o==0) next;
        delta=(n-o)/o*100;
        if (delta>5 || delta<-5) {
          printf "%s digits=%s old=%s new=%s delta=%+.1f%%\n", $4, $5, o, n, delta;
          if (delta>10) bad=1;
        }
      }
      END { exit (bad ? 1 : 0) }' "$base" "$cur"
    ;;
  *)
    fail "usage: benchcompare.sh write [out.csv] | merge out.csv in.csv... | compare baseline.csv current.csv"
    ;;
esac
