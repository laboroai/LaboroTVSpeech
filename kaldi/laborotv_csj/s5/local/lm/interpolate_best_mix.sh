#!/usr/bin/env bash

# Interpolates multiple language models while estimating the best mixture weights,
# using SRILM's compute-best-mix.

. cmd.sh
. path.sh
set -e

# Begin configuration section.
ngram_order=3
dev_text=
src_lexicons=
src_lms=
remove_utt_ids_from_dev_text=false

echo "$0 $@" # Print the command line for logging

. utils/parse_options.sh || exit 1

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <lm_name>"
  echo "e.g.: $0 --dev-text dev.txt --src-lexicons \"lexicon1.txt lexicon2.txt\" --src-lms \"lm1.arpa.gz lm2.arpa.gz\" interp-lm1-lm2"
  echo "main options: "
  echo "  --dev-text <dev-text> (required)          # dev text for estimating mixture weights"
  echo "  --src-lexicons <src-lexicons> (required)  # lexicon.txt of each LM to interpolate"
  echo "  --src-lms <src-lms> (required)            # LMs to interpolate"
  echo "  --ngram-order <ngram-order>:              # default 3"
  exit 1
fi

for file in ${dev_text} ${src_lexicons} ${src_lms}; do
  if [[ ! -e ${file} ]]; then
    echo "$0: expected file ${file} to exist."
    exit 1
  fi
done

lm_name=$1

readonly LM_SRI_DIR="data/local/lm_${lm_name}"
readonly LM="${LM_SRI_DIR}/lm.o${ngram_order}g.kn.gz"

# Estimate the best mixture weights
if [[ ! -e ${LM} ]]; then
  mkdir -p ${LM_SRI_DIR}
  if ${remove_utt_ids_from_dev_text}; then
    cut -d' ' -f2- ${dev_text} >${LM_SRI_DIR}/dev.txt
    dev_text=${LM_SRI_DIR}/dev.txt
  fi

  ppls=()
  for src_lm in ${src_lms}; do
    echo "$0: computing sentence scores and perplexities from the sentences in ${dev_text} with ${src_lm}"
    src_lm_dir=$(dirname ${src_lm})
    ppl="${src_lm_dir}/dev.ppl"
    if [[ ! -e ${ppl} ]]; then
      ngram \
        -unk \
        -lm ${src_lm} \
        -ppl ${dev_text} \
        -debug 2 >&${ppl}
    fi
    ppls+=(${ppl})
  done

  compute-best-mix "${ppls[@]}" >${LM_SRI_DIR}/best_mix_weights
  cat ${LM_SRI_DIR}/best_mix_weights

  mix_weights=($(head -n1 ${LM_SRI_DIR}/best_mix_weights | perl -pe 's/.*\((.*)\).*/\1/g'))

  lms=(${src_lms})
  : >"${LM_SRI_DIR}/mix_lm_list.txt"
  for lm_idx in $(seq 0 $((${#lms[@]} - 1))); do
    echo "${lms[lm_idx]} -weight ${mix_weights[lm_idx]}" >>"${LM_SRI_DIR}/mix_lm_list.txt"
  done
  cat "${LM_SRI_DIR}/mix_lm_list.txt"

  # Inetrpolate
  ngram \
    -debug 3 \
    -lm "${LM_SRI_DIR}/mix_lm_list.txt" \
    -read-mix-lms \
    -unk \
    -map-unk "<unk>" \
    -write-lm ${LM}
fi

cat \
  ${src_lexicons} |
  LC_ALL=C sort -u \
    >${LM_SRI_DIR}/lexicon.txt

local/lm/prepare_lang_from_arpa.sh \
  --suffix "_${lm_name}" \
  ${LM} ${LM_SRI_DIR}/lexicon.txt

echo "$0: Done!"
