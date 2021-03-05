#!/usr/bin/env bash

# Data preparation for LaboroTVSpeech

. ./path.sh
set -e # exit on error

dst_dir=data

. utils/parse_options.sh

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <corpus_dir>"
  exit 1
fi

CORPUS_DIR=$1

# Data
for x in train dev; do
  echo "$0: Making ${dst_dir}/${x} ..."
  mkdir -p ${dst_dir}/${x}
  perl -pe 's/,/ /' ${CORPUS_DIR}/data/${x}/text.csv >${dst_dir}/${x}/text
  cut -d',' -f1 ${CORPUS_DIR}/data/${x}/text.csv |
    awk -v dir=${CORPUS_DIR}/data/${x}/wav/ "{print dir\$1\".wav\"}" |
    sort |
    perl -pe 's,(.*/)([^/]*)(\.wav),\2 \1\2\3,g' \
      >${dst_dir}/${x}/wav.scp
  # find -L ${CORPUS_DIR}/data/${x}/wav -name "*.wav" |
  #   sort |
  #   perl -pe 's,(.*/)([^/]*)(\.wav),\2 \1\2\3,g' \
  #     >data/${x}/wav.scp

  # Make a dumb utt2spk and spk2utt,
  # where each utterance corresponds to a unique speaker.
  awk '{print $1,$1_spk}' ${dst_dir}/${x}/text >${dst_dir}/${x}/utt2spk
  utils/utt2spk_to_spk2utt.pl ${dst_dir}/${x}/utt2spk >${dst_dir}/${x}/spk2utt

  utils/data/get_utt2dur.sh ${dst_dir}/${x}

  utils/fix_data_dir.sh ${dst_dir}/${x}
  utils/validate_data_dir.sh --no-feats ${dst_dir}/${x}
done

echo "$0: done preparing data directories"
