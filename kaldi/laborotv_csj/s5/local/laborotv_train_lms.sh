#!/bin/bash

# Almost the same as the one used in the CSJ recipe.
# 2020 Only slightly modified by Shintaro Ando at Laboro.AI, Inc.
#
# This version allows to change the filename of the LM being built,
# and also supports text files without utterance ids in their 1st row
# by setting `--cut-begin-field 1`.

# 2016 Modified by Takafumi Moriya at Tokyo Institute of Technology
# for Japanese speech recognition using CSJ.

# Copyright 2013  Arnab Ghoshal
#                 Johns Hopkins University (author: Daniel Povey)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# To be run from one directory above this script.

# Begin configuration section.
cut_begin_field=2
lm_name="laborotv"
# end configuration sections

help_message="Usage: "$(basename $0)" [options] <train-txt> <dict> <out-dir>
Train language models for LaboroTVSpeech.\n
options:
  --help          # print this message and exit
"

. utils/parse_options.sh

if [ $# -ne 3 ]; then
  printf "$help_message\n"
  exit 1
fi

text=$1
lexicon=$2
dir=$3
. ./path.sh

for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1
done

loc=$(which ngram-count)
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=${KALDI_ROOT}/tools/srilm/bin/i686-m64
  else
    sdir=${KALDI_ROOT}/tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir. See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi

set -o errexit
mkdir -p $dir
export LC_ALL=C

heldout_sent=10000
cut -d' ' -f${cut_begin_field}- $text | gzip -c >$dir/train.all.gz
cut -d' ' -f${cut_begin_field}- $text | tail -n +$heldout_sent | gzip -c >$dir/train.gz
cut -d' ' -f${cut_begin_field}- $text | head -n $heldout_sent >$dir/heldout

cut -d' ' -f1 $lexicon >$dir/wordlist

ngram-count -text $dir/train.gz -order 3 -limit-vocab -vocab $dir/wordlist \
  -unk -map-unk "<unk>" -kndiscount -interpolate -lm $dir/${lm_name}.o3g.kn.gz
echo "PPL for LM:"
ngram -unk -lm $dir/${lm_name}.o3g.kn.gz -ppl $dir/heldout
ngram -unk -lm $dir/${lm_name}.o3g.kn.gz -ppl $dir/heldout -debug 2 >&$dir/ppl2
