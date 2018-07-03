#!/bin/bash 

# Uses the QCRI vowelized Arabic lexicon.
# Converts the Buckwalter encoding to utf8.
# Uses the perl module Encode::Arabic::Buckwalter for the conversion.

. ./cmd.sh
. ./path.sh
stage=0

. ./utils/parse_options.sh

set -e
set -o pipefail
set u

# Do not change tmpdir, other scripts under local depend on it
tmpdir=data/local/tmp

if [ $stage -le 0 ]; then
  # Downloads archive to this script's directory
  local/tamsa_download.sh
fi

# preparation stages will store files under data/
# Delete the entire data directory when restarting.
if [ $stage -le 1 ]; then
  local/prepare_data.sh
fi

if [ $stage -le 2 ]; then
  local/qcri_lexicon_download.sh 
fi

if [ $stage -le 3 ]; then
  mkdir -p $tmpdir/dict
  local/qcri_buckwalter2utf8.pl > $tmpdir/dict/qcri_utf8.txt
  # prepare a dictionary
  local/prepare_dict.sh $tmpdir/dict/qcri_utf8.txt
fi

if [ $stage -le 4 ]; then
  # prepare the lang directory
  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang
fi

if [ $stage -le 5 ]; then
  # prepare lm on training and test transcripts
  local/prepare_lm.sh
fi

if [ $stage -le 6 ]; then
  utils/format_lm.sh \
    data/lang data/local/lm/lm_threegram.arpa.gz \
    data/local/dict/lexicon.txt data/lang_test
fi

if [ $stage -le 7 ]; then
  # extract acoustic features
  for fld in dev devtest train test; do
    steps/make_plp_pitch.sh data/$fld exp/make_plp_pitch/$fld plp_pitch
    utils/fix_data_dir.sh data/$fld
    steps/compute_cmvn_stats.sh data/$fld exp/make_plp_pitch plp_pitch
    utils/fix_data_dir.sh data/$fld
  done
fi

if [ $stage -le 8 ]; then
    echo "$0: monophone training"
    steps/train_mono.sh  data/train data/lang exp/mono
fi

if [ $stage -le 9 ]; then
  # monophone evaluation
  (
    # make decoding graph for monophones
    utils/mkgraph.sh data/lang_test exp/mono exp/mono/graph

    # test monophones
    for x in dev devtest test; do
      steps/decode.sh  exp/mono/graph data/$x exp/mono/decode_${x}
    done
  ) &
fi

if [ $stage -le 10 ]; then
    # align with monophones
    steps/align_si.sh  data/train data/lang exp/mono exp/mono_ali
fi

if [ $stage -le 11 ]; then
    echo "$0: Starting  triphone training in exp/tri1"
    steps/train_deltas.sh \
        --cluster-thresh 100 500 5000 data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 12 ]; then
    # test cd gmm hmm models
    # make decoding graphs for tri1
    (
        utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph

        # decode test data with tri1 models
	for x in dev devtest test; do
            steps/decode.sh exp/tri1/graph data/$x exp/tri1/decode_${x}
	    done
    ) &
fi

if [ $stage -le 11 ]; then
    # align with triphones
    steps/align_si.sh  data/train data/lang exp/tri1 exp/tri1_ali
fi

if [ $stage -le 12 ]; then
    echo "$0: Starting (lda_mllt) triphone training in exp/tri2b"
    steps/train_lda_mllt.sh \
        --splice-opts "--left-context=3 --right-context=3" 700 8000 \
        data/train data/lang exp/tri1_ali exp/tri2b
fi

if [ $stage -le 13 ]; then
    (
        #  make decoding FSTs for tri2b models
        utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph

        # decode  test with tri2b models
	for x in dev devtest test; do
            steps/decode.sh exp/tri2b/graph data/$x exp/tri2b/decode_${x}
	    done
    ) &
fi

if [ $stage -le 14 ]; then
    # align with lda and mllt adapted triphones
    steps/align_si.sh \
	--use-graphs true data/train data/lang exp/tri2b exp/tri2b_ali
fi

if [ $stage -le 15 ]; then
    echo "$0: Starting (SAT) triphone training in exp/tri3b"
    steps/train_sat.sh 800 10000 data/train data/lang exp/tri2b_ali exp/tri3b
fi

if [ $stage -le 16 ]; then
    (
        # make decoding graphs for SAT models
        utils/mkgraph.sh data/lang_test exp/tri3b exp/tri3b/graph

        # decode test sets with tri3b models
	for x in dev devtest test; do
            steps/decode_fmllr.sh exp/tri3b/graph data/$x exp/tri3b/decode_${x}
	done
    ) &
fi

if [ $stage -le 17 ]; then
    # align with tri3b models
    echo "$0: Starting exp/tri3b_ali"
    steps/align_fmllr.sh data/train data/lang exp/tri3b exp/tri3b_ali
fi

if [ $stage -le 19 ]; then
    # train and test chain models
    local/chain/run_tdnn.sh
fi
