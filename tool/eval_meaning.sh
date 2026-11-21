#!/usr/bin/env bash
# Device-model eval without and with the e5 vectors (#929), slim and full; needs Ollama's GPU.
#   tool/eval_meaning.sh <ollama model> <e5 folder> <onnxruntime library> [out folder]
set -euo pipefail
model=$1 e5=$2 ort=$3 out=${4:-.dev-home/eval-meaning}
mkdir -p "$out"
export NOTELORE_HOME=${NOTELORE_HOME:-.dev-home}
# One binary for every run: `dart run` rebuilds and would race a run in progress.
dart build cli -t packages/notelore_core/bin/notelore_dev.dart -o "$out/bin" >/dev/null
dev=$(find "$out/bin" -name 'notelore_dev*' -type f | head -n 1)
for set in cases holdout; do
  for prompt in slim full; do
    flags=(--provider=ollama "--model=$model" --greedy "--cases=eval/$set.json")
    [[ $prompt == slim ]] && flags+=(--slim)
    "$dev" eval "${flags[@]}" >"$out/$set-$prompt-before.txt" 2>&1
    "$dev" eval "${flags[@]}" "--meaning=$e5" "--ort=$ort" >"$out/$set-$prompt-after.txt" 2>&1
  done
done
tail -n 3 "$out"/*.txt
