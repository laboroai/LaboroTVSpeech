#!/usr/bin/env bash

# Create symbolic links to scripts required to prepare CSJ data in local/

. ./path.sh
set -e # exit on error

if [ -z ${KALDI_ROOT} ]; then
  echo "$0: KALDI_ROOT is not set."
  exit 1
fi

if [ "${KALDI_ROOT:0:1}" = "/" ]; then
  # if KALDI_ROOT is an absolute path
  csj_local=${KALDI_ROOT}/egs/csj/s5/local
else
  # if KALDI_ROOT is a relative path
  csj_local=../${KALDI_ROOT}/egs/csj/s5/local
fi

if [ ! -d ${csj_local} ]; then
  echo "$0: ${csj_local} does not exist."
  exit 1
fi

scripts=(
  ${csj_local}/csj_make_trans
  ${csj_local}/csj_data_prep.sh
  ${csj_local}/csj_prepare_dict.sh
  ${csj_local}/csj_train_lms.sh
  ${csj_local}/csj_eval_data_prep.sh
)

(
  cd local
  for script in ${scripts[@]}; do
    ln -sfv ${script}
  done
)