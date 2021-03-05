#!/usr/bin/env bash

# Preparing CSJ data
#
# Scripts in this file were imported from egs/csj/run.sh
# with slight modifications mainly to change destination directories

. ./path.sh
. ./cmd.sh
set -e # exit on error

echo "$0 $@"

mode=3  # using all CSJ data
use_dev=false

. utils/parse_options.sh

#check existing directories
if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <csj_root> <csj_ver> <dst_data_root>"
  echo "e.g: $0 --mode 3 /mnt/data/CSJ usb data/csj"
  echo "Options:"
  echo "  --mode: mode-number passed to csj_make_trans/csj_autorun.sh."
  echo "          mode-number can be 0, 1, 2, 3."
  echo "           (0=using academic lecture and other data"
  echo "            1=using academic lecture data,"
  echo "            2=using all data except for dialog data, "
  echo "            3=using all data)"
  echo "          As LaboroTVSpeech has 2000+ hours of data,"
  echo "          mode-number defaults to 3 in this script."
  exit 1;
fi

CSJDATATOP=$1
CSJVER=$2
dst_data_root=$3

mkdir -p ${dst_data_root}/local

echo "$0: Creating symlinks to csj's data preparation scripts in local/"
local/csj_symlink_scripts.sh

if [ ! -e ${dst_data_root}/csj-data/.done_make_all ]; then
  echo "CSJ transcription file does not exist"
  #local/csj_make_trans/csj_autorun.sh <RESOUCE_DIR> <MAKING_PLACE(no change)> || exit 1;
  local/csj_make_trans/csj_autorun.sh $CSJDATATOP ${dst_data_root}/csj-data $CSJVER
fi
wait

[ ! -e ${dst_data_root}/csj-data/.done_make_all ]\
    && echo "Not finished processing CSJ data" && exit 1;

# Prepare Corpus of Spontaneous Japanese (CSJ) data.
# Processing CSJ data to KALDI format based on switchboard recipe.
# local/csj_data_prep.sh <SPEECH_and_TRANSCRIPTION_DATA_DIRECTORY> [ <mode_number> ]
# mode_number can be 0, 1, 2, 3 (0=default using "Academic lecture" and "other" data,
#                                1=using "Academic lecture" data,
#                                2=using All data except for "dialog" data, 3=using All data )
local/csj_data_prep.sh ${dst_data_root}/csj-data ${mode}

# To use exactly the same script as the original CSJ recipe,
# we use a symbolic link and a temporal directory,
# as the original csj_prepare_dict.sh creates directory to data/,
local/csj_prepare_dict.sh

# Move directories which were directly created in data/ to ${dst_data_root}
mv data/local/train ${dst_data_root}/local
mv data/train ${dst_data_root}
mv data/local/dict* ${dst_data_root}/local

utils/prepare_lang.sh --num-sil-states 4 ${dst_data_root}/local/dict_nosp "<unk>" ${dst_data_root}/local/lang_nosp ${dst_data_root}/lang_nosp

# Now train the language models.
local/csj_train_lms.sh ${dst_data_root}/local/train/text ${dst_data_root}/local/dict_nosp/lexicon.txt ${dst_data_root}/local/lm

# We don't really need all these options for SRILM, since the LM training script
# does some of the same processing (e.g. -subset -tolower)
srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
LM=${dst_data_root}/local/lm/csj.o3g.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
  ${dst_data_root}/lang_nosp $LM ${dst_data_root}/local/dict_nosp/lexicon.txt ${dst_data_root}/lang_nosp_csj_tg

# Data preparation and formatting for evaluation set.
# CSJ has 3 types of evaluation data
#local/csj_eval_data_prep.sh <SPEECH_and_TRANSCRIPTION_DATA_DIRECTORY_ABOUT_EVALUATION_DATA> <EVAL_NUM>
for eval_num in eval1 eval2 eval3 ; do
    local/csj_eval_data_prep.sh ${dst_data_root}/csj-data/eval $eval_num
done
mv data/eval{1,2,3} data/csj
mv data/local/eval{1,2,3} data/csj/local

# Now make MFCC features.
for x in train eval1 eval2 eval3; do
  steps/make_mfcc.sh --nj 50 --cmd "$train_cmd" ${dst_data_root}/$x
  steps/compute_cmvn_stats.sh ${dst_data_root}/$x
  utils/fix_data_dir.sh ${dst_data_root}/$x
done

echo "Finish creating MFCCs"

# Use the first 4k sentences as dev set.  Note: when we trained the LM, we used
# the 1st 10k sentences as dev set, so the 1st 4k won't have been used in the
# LM training data.   However, they will be in the lexicon, plus speakers
# may overlap, so it's still not quite equivalent to a test set.
if $use_dev ;then
    dev_set=train_dev
    utils/subset_data_dir.sh --first ${dst_data_root}/train 4000 ${dst_data_root}/$dev_set # 6hr 31min
    n=$[`cat ${dst_data_root}/train/segments | wc -l` - 4000]
    utils/subset_data_dir.sh --last ${dst_data_root}/train $n ${dst_data_root}/train_nodev
else
    cp -r ${dst_data_root}/train ${dst_data_root}/train_nodev
fi

# Calculate the amount of utterance segmentations.
# perl -ne 'split; $s+=($_[3]-$_[2]); END{$h=int($s/3600); $r=($s-$h*3600); $m=int($r/60); $r-=$m*60; printf "%.1f sec -- %d:%d:%.1f\n", $s, $h, $m, $r;}' ${dst_data_root}/train/segments

# Now-- there are 162k utterances (240hr 8min), and we want to start the
# monophone training on relatively short utterances (easier to align), but want
# to exclude the shortest ones.
# Therefore, we first take the 100k shortest ones;
# remove most of the repeated utterances, and
# then take 10k random utterances from those (about 8hr 9mins)
utils/subset_data_dir.sh --shortest ${dst_data_root}/train_nodev 100000 ${dst_data_root}/train_100kshort
utils/subset_data_dir.sh ${dst_data_root}/train_100kshort 30000 ${dst_data_root}/train_30kshort

# Take the first 100k utterances (about half the data); we'll use
# this for later stages of training.
utils/subset_data_dir.sh --first ${dst_data_root}/train_nodev 100000 ${dst_data_root}/train_100k
utils/data/remove_dup_utts.sh 200 ${dst_data_root}/train_100k ${dst_data_root}/train_100k_nodup  # 147hr 6min

# Finally, the full training set:
utils/data/remove_dup_utts.sh 300 ${dst_data_root}/train_nodev ${dst_data_root}/train_nodup  # 233hr 36min

echo "$0: Done preparing CSJ's data directories in ${dst_data_root}."
