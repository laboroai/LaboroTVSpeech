#!/usr/bin/env bash
set -euo pipefail

# Create a kaldi-format lang/ directory with FST
# from arpa-format LM and lexicon.txt

echo "$0 $@" # Print the command line for logging

# Begin configuration
suffix=""

. utils/parse_options.sh

if [ $# != 2 ]; then
  echo "Usage: $0 <arpa-lm> <lexicon>"
  echo "e.g.:  $0 data/local/lm_oscar/oscar.o3g.kn.gz data/local/lm_oscar/lexicon.txt"
  echo ""
  echo "options"
  echo "  --suffix <suffix>              # suffix used as dict_nosp<suffix> etc."
  exit 1
fi

arpa_lm=$1
lexicon=$2

for file in ${arpa_lm} ${lexicon}; do
  if [ ! -f ${file} ]; then
    echo "$0: ${file} does not exist."
    exit 1
  fi
done

local/lm/prepare_dict.sh ${lexicon} data/local/dict_nosp${suffix}

utils/prepare_lang.sh \
  --num-sil-states 4 \
  data/local/dict_nosp${suffix} \
  "<unk>" \
  data/local/lang_nosp${suffix} \
  data/lang_nosp${suffix}

srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
  data/lang_nosp${suffix} \
  ${arpa_lm} \
  data/local/dict_nosp${suffix}/lexicon.txt \
  data/lang_nosp${suffix}_tg

echo "$0: done creating data/lang_nosp${suffix}_tg."
