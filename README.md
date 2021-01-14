# LaboroTVSpeech

A large-scale Japanese speech corpus on TV recordings

## About the Corpus

LaboroTVSpeech is a large-scale Japanese speech corpus built from broadcast TV recordings and their subtitles.
Our current release contains over 2,000 hours of speech.

### Details

- All audio samples were segmented based on the boudaries of the original subtitles, with sampling rates of 16 KHz.

- Each speech semgments are tokenized into sequence of words using [MeCab](https://taku910.github.io/mecab/) with [mecab-ipadic-NEologd](https://github.com/neologd/mecab-ipadic-neologd) as a dictionary.
- Each word token contains a simple morpheme tag such as 名詞 (noun) or 動詞 (verb), obatained through preprocessing the original subtitles.
- From the original TV audio and subtitles, we have extracted the speech segments where we were able to align the audio and subtitle segment with high confidence.
  - We iteraively used [segment_long_utterances_nnet3.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/steps/cleanup/segment_long_utterances_nnet3.sh) and [clean_and_segment_data_nnet3.sh](https://github.com/kaldi-asr/kaldi/blob/master/egs/wsj/s5/steps/cleanup/clean_and_segment_data_nnet3.sh).
- All speech segments are randomly shuffled.

### Subsets

|                      | train  | dev   |
| -------------------- | ------ | ----- |
| Audio length (hours) | 2036.2 | 13.7  |
| # Audio segments     | 1.6 M  | 12 K  |
| # Words (tokens)     | 22 M   | 147 K |

### Precaution

- Some words' pronunciation or morpheme tag may be incorrect, especially for casual words.
  - e.g. 「すげえ」 (_Sugē_, casual form of _Sugoi_=great, very, etc.) → 「すげ+動詞 え+フィラー」(tokenized as verb + filler)
- Each speech segment in this dataset **does not** have a speaker tag. You have to treat each segment as an utterance spoken by a unique speaker.
- **We do not provide a test set** in this corpus, because it was nearly imporssible not to make speakers in the test set appear in the training or development set considering that many celebrities appear in several programs.
  - In stead of the test set of LaboroTVSpeech, you may use [TEDxJP-10K](#tedxjp-10k-dataset).

## How to get the corpus

[This page](https://laboro.ai/column/eg-laboro-tv-corpus-jp/) describes how to apply for downloading the corpus in Japanese. English explanation will be added in near future.

## Recipe for Kaldi Speech Recognition Tooklit

We have evaluated LaboroTVSpeech by building an ASR model using the [Kaldi Speech Recognition Toolkit](https://github.com/kaldi-asr/kaldi).
The recipe is based on Kaldi's [official CSJ recipe](https://github.com/kaldi-asr/kaldi/tree/master/egs/csj/s5).

As a test set, we used [TEDxJP-10K](https://github.com/laboroai/TEDxJP-10K) ASR evalution dataset.

### How to train an ASR model

Firstly, copy `kaldi/laborotv` to your `$KALDI_ROOT/egs`. Then, extract "LaboroTVSpeech_v1.0b.tar.gz" and modify `LABOROTV_DATA_ROOT=` line in `s5/run.sh` to match your environment.

For the test test, construct TEDxJP-10K dataset from [TEDxJP-10K github page](https://github.com/laboroai/TEDxJP-10K) and modify `TEDXJP_DATA_ROOT=` line in `s5/run.sh` to the location where you store the dataset.

Finally, execute `s5/run.sh` to start training.

### Optional arguments for `run.sh`

By default, `run.sh` will train both acoustic model and language model with only LabotoTVSpeech corpus and do the testing using TEDxJP-10K dataset. There are several optional arguments you can set to control how we train a langugae model and how we test the trained model.

- `--include-tedx false`
  - With this option, we will not use TEDxJP-10K and, hence, no testing will be conducted.

- `--include-oscar-lm true`
  - With this option, we will also use a LM built from OSCAR corpus.
  <!-- - This option supposes 3-gram count file of OSCAR already exists in `data/local/oscar.gz`. -->
  - You have to copy an arpa-format LM (`oscar_200Kvocab_prune1e-8.o3g.kn.gz`) and lexicon.txt to `data/local/lm_oscar` beforehand.
  - Read [OSCAR Language Model](#oscar-language-model) for details.

- `--include-lm-interp true`
  - With this option, the script builds TV+OSCAR-LM by interpolating the default TV-LM and OSCAR-LM.
  - This option is allowed only if `--include-oscar-lm true` is set.

For example, if you want to train a language model with OSCAR corpus with out do testing, execute the below line instead.
```
./run.sh --include-tedx false --include-oscar-lm true
```

## OSCAR Language Model

### Overview

This LM was trained using the [OSCAR](https://oscar-corpus.com/) corpus containing 100 GB of web-crawled Japanese text. We estimated the pronunciations of the words in the lexicon in the same way as the LaboroTVSpeech. When building LMs, we have selected the vocabulary based on frequency counts.

### Download

- [oscar_3gram_lm_v1.0.tar.gz](http://assets.laboro.ai.s3.amazonaws.com/laborotvspeech/oscar_3gram_lm_v1.0.tar.gz)
  - 3-gram counts
  - 3-gram LM with vocabulary size = 200K (pruned 1e-8)
  - pronunciation dictionaries

## License

The content of this repository and the OSCAR Language model (excluding LaboroTVSpeech corpus itself) is released under Apache License v2.
