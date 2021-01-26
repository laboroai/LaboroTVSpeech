#!/usr/bin/env bash

# Copyright  2020 Laboro.AI, Inc.
#                 (Authors: Shintaro Ando and Hiromasa Fujihara)
# Apache 2.0

# This recipe is based on the two following recipes:
# - We imported the hyperparameters and the training procedures from
#   the CSJ recipe by Takafumi Moriya, Tomohiro Tanaka, Takahiro Shinozaki and Shinji Watanabe
#   in the egs/csj/s5/ directory.
# - We imported the `stage`s from
#   the WSJ corpus recipe in the egs/wsj/s5/ directory.

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.
# Caution: some of the graph creation steps use quite a bit of memory, so you
# should run this on a machine that has sufficient memory.

. cmd.sh
. path.sh
set -e

nj=50
nj_decode=10

stage=0
dnn_stage=0

dev_set="dev"
test_sets=""
test_lang_names="lang_laborotv_tg"
oscar_lm_name="oscar_200Kvocab_prune1e-8"

# options to include additional testing dataset & LMs
include_tedx=true
include_oscar_lm=false
include_lm_interp=false

. utils/parse_options.sh

LABOROTV_DATA_ROOT="/mnt/data/LaboroTVSpeech_v1.0c"
TEDXJP_DATA_ROOT="/mnt/data/TEDxJP-10K_v1.1"

# Handle options
if ${include_tedx}; then
  test_sets="tedx-jp-10k"
fi

if ${include_oscar_lm}; then
  test_lang_names="${test_lang_names} lang_nosp_${oscar_lm_name}_tg"
fi

if ${include_lm_interp}; then
  if [[ ! ${include_oscar_lm} ]]; then
    echo "$0: '--include-oscar true' should be set when '--include-lm-interp true'"
  fi
  test_lang_names="${test_lang_names} lang_nosp_tv-${oscar_lm_name}-interp_tg"
fi

if [[ ${stage} -le 0 ]]; then
  # Prepare train & dev set
  local/laborotv_data_prep.sh ${LABOROTV_DATA_ROOT}

  if ${include_tedx}; then
    # Prepare TEDx-JP-10K to use as eval set.
    local/tedx-jp-10k_data_prep.sh ${TEDXJP_DATA_ROOT}
  fi
  
  local/lm/prepare_dict.sh \
    ${LABOROTV_DATA_ROOT}/data/lexicon.txt data/local/dict_nosp

  utils/prepare_lang.sh --num-sil-states 4 data/local/dict_nosp "<unk>" data/local/lang_nosp data/lang_nosp

  # Now train the language models.
  local/laborotv_train_lms.sh \
    data/train/text data/local/dict_nosp/lexicon.txt data/local/lm

  # We don't really need all these options for SRILM, since the LM training script
  # does some of the same processing (e.g. -subset -tolower)
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  LM=data/local/lm/laborotv.o3g.kn.gz
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    data/lang_nosp $LM data/local/dict_nosp/lexicon.txt data/lang_nosp_laborotv_tg

  if ${include_oscar_lm}; then
    local/lm/prepare_lang_from_arpa.sh \
      --suffix "_${oscar_lm_name}" \
      "data/local/lm_oscar/${oscar_lm_name}.o3g.kn.gz" \
      "data/local/lm_oscar/lexicon.txt"
  fi

  if ${include_lm_interp}; then
    local/lm/interpolate_best_mix.sh \
      --dev-text "data/dev/text" \
      --remove-utt-ids-from-dev-text true \
      --src-lexicons "data/local/dict_nosp/lexicon.txt data/local/dict_nosp_${oscar_lm_name}/lexicon.txt" \
      --src-lms "data/local/lm/laborotv.o3g.kn.gz data/local/lm_oscar/${oscar_lm_name}.o3g.kn.gz" \
      "tv-${oscar_lm_name}-interp"
  fi

  for dir_name in train ${test_sets} ${dev_set}; do
    steps/make_mfcc.sh --nj ${nj} data/${dir_name}
    steps/compute_cmvn_stats.sh data/${dir_name}
    utils/validate_data_dir.sh data/${dir_name}
  done

  # We create subsets for training in earlier stages
  # in the same way as the CSJ recipe
  utils/subset_data_dir.sh \
    --shortest data/train \
    100000 \
    data/train_100kshort

  utils/subset_data_dir.sh \
    data/train_100kshort \
    30000 \
    data/train_30kshort

  utils/subset_data_dir.sh \
    --first \
    data/train \
    100000 \
    data/train_100k
fi

if [[ ${stage} -le 1 ]]; then
  # mono
  steps/train_mono.sh --nj ${nj} --cmd "$train_cmd" \
    data/train_30kshort \
    data/lang_nosp \
    exp/mono
fi

if [[ ${stage} -le 2 ]]; then
  # tri1
  steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
    data/train_100k \
    data/lang_nosp \
    exp/mono \
    exp/mono_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
    3200 30000 \
    data/train_100k \
    data/lang_nosp \
    exp/mono_ali \
    exp/tri1

  graph_dir=exp/tri1/graph_nosp_laborotv_tg
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_nosp_laborotv_tg exp/tri1 $graph_dir
  for eval_id in ${test_sets} $dev_set; do
    steps/decode_si.sh --nj ${nj_decode} --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir data/$eval_id exp/tri1/decode_nosp_laborotv_${eval_id}
  done
fi

if [[ ${stage} -le 3 ]]; then
  # tri2
  steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
    data/train_100k \
    data/lang_nosp \
    exp/tri1 \
    exp/tri1_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
    4000 70000 \
    data/train_100k \
    data/lang_nosp \
    exp/tri1_ali \
    exp/tri2

  # The previous mkgraph might be writing to this file.  If the previous mkgraph
  # is not running, you can remove this loop and this mkgraph will create it.
  while [ ! -s data/lang_nosp_laborotv_tg/tmp/CLG_3_1.fst ]; do sleep 60; done
  sleep 20 # in case still writing.
  graph_dir=exp/tri2/graph_nosp_laborotv_tg
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_nosp_laborotv_tg exp/tri2 $graph_dir
  for eval_id in ${test_sets} $dev_set; do
    steps/decode.sh --nj ${nj_decode} --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir data/$eval_id exp/tri2/decode_nosp_laborotv_${eval_id}
  done
fi

if [[ ${stage} -le 4 ]]; then
  # tri3
  # From now, we start with the LDA+MLLT system
  steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
    data/train_100k \
    data/lang_nosp \
    exp/tri2 \
    exp/tri2_ali_100k

  # From now, we start using all of the data (except some duplicates of common
  # utterances, which don't really contribute much).
  steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
    data/train \
    data/lang_nosp \
    exp/tri2 \
    exp/tri2_ali

  # Do another iteration of LDA+MLLT training, on all the data.
  steps/train_lda_mllt.sh \
    --cmd "$train_cmd" \
    6000 140000 \
    data/train \
    data/lang_nosp \
    exp/tri2_ali \
    exp/tri3

  graph_dir=exp/tri3/graph_nosp_laborotv_tg
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_nosp_laborotv_tg exp/tri3 $graph_dir
  for eval_id in ${test_sets} $dev_set; do
    steps/decode.sh --nj ${nj_decode} --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir data/$eval_id exp/tri3/decode_nosp_laborotv_${eval_id}
  done
fi

if [[ ${stage} -le 5 ]]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.
  steps/get_prons.sh --cmd "$train_cmd" \
    data/train \
    data/lang_nosp \
    exp/tri3
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/local/dict_nosp exp/tri3/pron_counts_nowb.txt exp/tri3/sil_counts_nowb.txt \
    exp/tri3/pron_bigram_counts_nowb.txt data/local/dict

  utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang
  LM=data/local/lm/laborotv.o3g.kn.gz
  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    data/lang $LM data/local/dict/lexicon.txt data/lang_laborotv_tg

  graph_dir=exp/tri3/graph_laborotv_tg
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_laborotv_tg exp/tri3 $graph_dir
  for eval_id in ${test_sets} $dev_set; do
    steps/decode.sh --nj ${nj_decode} --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir data/$eval_id exp/tri3/decode_laborotv_tg_${eval_id}
  done
fi

if [[ ${stage} -le 6 ]]; then
  # Train tri4, which is LDA+MLLT+SAT, on all the data.
  steps/align_fmllr.sh --nj ${nj} --cmd "$train_cmd" \
    data/train \
    data/lang \
    exp/tri3 \
    exp/tri3_ali

  steps/train_sat.sh --cmd "$train_cmd" \
    11500 200000 \
    data/train \
    data/lang \
    exp/tri3_ali \
    exp/tri4

  graph_dir=exp/tri4/graph_laborotv_tg
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_laborotv_tg exp/tri4 $graph_dir
  for eval_id in ${test_sets} $dev_set; do
    steps/decode_fmllr.sh --nj ${nj_decode} --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir data/${eval_id} exp/tri4/decode_laborotv_tg_${eval_id}
  done
fi

if [[ ${stage} -le 7 ]]; then
  # nnet3 TDNN+Chain
  local/chain/run_tdnn.sh \
    --test-sets "${test_sets}" \
    --test-lang-names "${test_lang_names}" \
    --stage ${dnn_stage}
fi

exit 0

# getting results (see RESULTS file)
# for eval_id in ${test_sets} $dev_set; do
#   echo "=== evaluation set $eval_id ==="
#   for x in exp/{tri,dnn}*/decode_*_${eval_id}*; do
#     [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh
#   done
# done
