#!/usr/bin/env bash

# Preparing LaboroTVSpeech data

. ./path.sh
. ./cmd.sh
set -e # exit on error

nj=50

. utils/parse_options.sh

#check existing directories
if [ $# -ne 2 ]; then
  echo "Usage: $0 [options] <laborotvspeech_root> <dst_data_root>"
  echo "e.g: $0 /mnt/data/LaboroTVSpeech data"
  exit 1;
fi

LABOROTV_DATA_ROOT=$1
dst_data_root=$2

local/laborotv_data_prep.sh \
  --dst-dir ${dst_data_root} \
  ${LABOROTV_DATA_ROOT}

local/lm/prepare_dict.sh \
  ${LABOROTV_DATA_ROOT}/data/lexicon.txt \
  ${dst_data_root}/local/dict_nosp

utils/prepare_lang.sh \
  --num-sil-states 4 \
  ${dst_data_root}/local/dict_nosp \
  "<unk>" \
  ${dst_data_root}/local/lang_nosp \
  ${dst_data_root}/lang_nosp

# Now train the language models.
local/laborotv_train_lms.sh \
  ${dst_data_root}/train/text \
  ${dst_data_root}/local/dict_nosp/lexicon.txt \
  ${dst_data_root}/local/lm

# We don't really need all these options for SRILM, since the LM training script
# does some of the same processing (e.g. -subset -tolower)
srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
LM=${dst_data_root}/local/lm/laborotv.o3g.kn.gz
utils/format_lm_sri.sh \
  --srilm-opts "$srilm_opts" \
  ${dst_data_root}/lang_nosp \
  $LM \
  ${dst_data_root}/local/dict_nosp/lexicon.txt \
  ${dst_data_root}/lang_nosp_laborotv_tg

for dir_name in train ${test_sets} ${dev_set}; do
  steps/make_mfcc.sh --nj ${nj} ${dst_data_root}/${dir_name}
  steps/compute_cmvn_stats.sh ${dst_data_root}/${dir_name}
  utils/validate_data_dir.sh ${dst_data_root}/${dir_name}
done

# We create subsets for training in earlier stages
# in the same way as the CSJ recipe
utils/subset_data_dir.sh \
  --shortest ${dst_data_root}/train \
  100000 \
  ${dst_data_root}/train_100kshort

utils/subset_data_dir.sh \
  ${dst_data_root}/train_100kshort \
  30000 \
  ${dst_data_root}/train_30kshort

utils/subset_data_dir.sh \
  --first \
  ${dst_data_root}/train \
  100000 \
  ${dst_data_root}/train_100k

echo "$0: Done preparing LaboroTVSpeech's data directores in ${dst_data_root}."