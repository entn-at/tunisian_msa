#!/bin/bash 

# Trains on 11 hours of speechfrom CTELL{ONE,TWO,THREE,FOUR,FIVE}
# Uses the QCRI vowelized Arabic lexicon.
# Converts the Buckwalter encoding to utf8.
# Uses the perl module Encode::Arabic::Buckwalter for the conversion.
# On Mac OSX use cpanm (cpanminus) to install perl module.
. ./cmd.sh
. ./path.sh
stage=0

. ./utils/parse_options.sh

set -e
set -o pipefail
set u

# Do not change tmpdir, other scripts under local depend on it
tmpdir=data/local/tmp

# The dev set is not publically available
dev_available=true

if [ $stage -le -1 ]; then
  # Downloads archive to this script's directory
    local/tamsa_download.sh

    local/qcri_lexicon_download.sh

    local/subs_download.sh
fi

# preparation stages will store files under data/
# Delete the entire data directory when restarting.
if [ $stage -le 0 ]; then
    local/prepare_data.sh
    if [ $dev_available=true ]; then
	local/prepare_dev_data.sh
	fi
fi

if [ $stage -le 1 ]; then
  mkdir -p $tmpdir/dict
  local/qcri_buckwalter2utf8.pl > $tmpdir/dict/qcri_utf8.txt
fi

if [ $stage -le 2 ]; then
  local/prepare_dict.sh $tmpdir/dict/qcri_utf8.txt
fi

if [ $stage -le 3 ]; then
  # prepare the lang directory
  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang
fi

if [ $stage -le 4 ]; then
  echo "Preparing the subs data for lm training."
  local/subs_prepare_data.pl 
fi

if [ $stage -le 5 ]; then
  echo "lm training."
  local/prepare_lm.sh  $tmpdir/subs/lm/in_vocabulary.txt
fi

if [ $stage -le 6 ]; then
  echo "Making grammar fst."
  utils/format_lm.sh \
    data/lang data/local/lm/trigram.arpa.gz data/local/dict/lexicon.txt \
    data/lang_test
fi

if [ $stage -le 7 ]; then
  # extract acoustic features
  for fld in devtest train test; do
    steps/make_plp_pitch.sh data/$fld exp/make_plp_pitch/$fld plp_pitch
    utils/fix_data_dir.sh data/$fld
    steps/compute_cmvn_stats.sh data/$fld exp/make_plp_pitch plp_pitch
    utils/fix_data_dir.sh data/$fld
  done

  if [ $dev_available=true ]; then
    steps/make_plp_pitch.sh data/dev exp/make_plp_pitch/dev plp_pitch
    utils/fix_data_dir.sh data/dev
    steps/compute_cmvn_stats.sh data/dev exp/make_plp_pitch plp_pitch
    utils/fix_data_dir.sh data/dev
fi
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
    for x in devtest test; do
      nspk=$(wc -l < data/$x/spk2utt)
      steps/decode.sh  --nj $nspk exp/mono/graph data/$x exp/mono/decode_${x}
    done

    if [ $dev_available=true ]; then
	nspk=$(wc -l < data/dev/spk2utt)
	steps/decode.sh  --nj $nspk exp/mono/graph data/dev exp/mono/decode_dev
fi
  ) &
fi

if [ $stage -le 10 ]; then
    # align with monophones
    steps/align_si.sh  data/train data/lang exp/mono exp/mono_ali
fi

if [ $stage -le 11 ]; then
    echo "$0: Starting  triphone training in exp/tri1"
    steps/train_deltas.sh \
        --boost-silence 1.25 1000 6000 data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 12 ]; then
  # test cd gmm hmm models
  # make decoding graphs for tri1
  (
    utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph

    # decode test data with tri1 models
    for x in devtest test; do
      nspk=$(wc -l < data/$x/spk2utt)
      steps/decode.sh --nj $nspk exp/tri1/graph data/$x exp/tri1/decode_${x}
    done

    if [ $dev_available=true ]; then
	nspk=$(wc -l < data/dev/spk2utt)
	steps/decode.sh --nj $nspk exp/tri1/graph data/dev exp/tri1/decode_dev
	fi
    ) &
fi

if [ $stage -le 13 ]; then
    # align with triphones
    steps/align_si.sh  data/train data/lang exp/tri1 exp/tri1_ali
fi

if [ $stage -le 14 ]; then
    echo "$0: Starting (lda_mllt) triphone training in exp/tri2b"
    steps/train_lda_mllt.sh \
        --splice-opts "--left-context=3 --right-context=3" 500 5000 \
        data/train data/lang exp/tri1_ali exp/tri2b
fi

if [ $stage -le 15 ]; then
  (
    #  make decoding FSTs for tri2b models
    utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph

    # decode  test with tri2b models
    for x in devtest test; do
      nspk=$(wc -l < data/$x/spk2utt)
      steps/decode.sh --nj $nspk exp/tri2b/graph data/$x exp/tri2b/decode_${x}
    done

    if [ $dev_available=true ]; then
	nspk=$(wc -l < data/dev/spk2utt)
      steps/decode.sh --nj $nspk exp/tri2b/graph data/dev exp/tri2b/decode_dev

  fi) &
fi

if [ $stage -le 16 ]; then
    # align with lda and mllt adapted triphones
    steps/align_si.sh \
	--use-graphs true data/train data/lang exp/tri2b exp/tri2b_ali
fi

if [ $stage -le 17 ]; then
    echo "$0: Starting (SAT) triphone training in exp/tri3b"
    steps/train_sat.sh 800 8000 data/train data/lang exp/tri2b_ali exp/tri3b
fi

if [ $stage -le 18 ]; then
    (
        # make decoding graphs for SAT models
        utils/mkgraph.sh data/lang_test exp/tri3b exp/tri3b/graph

        # decode test sets with tri3b models
	for x in devtest test; do
	    nspk=$(wc -l < data/$x/spk2utt)
            steps/decode_fmllr.sh --nj $nspk exp/tri3b/graph data/$x exp/tri3b/decode_${x}
	done

	if [ $dev_available=true ]; then
	    nspk=$(wc -l < data/dev/spk2utt)
            steps/decode_fmllr.sh --nj $nspk exp/tri3b/graph data/dev exp/tri3b/decode_dev
	    fi
    ) &
fi

if [ $stage -le 19 ]; then
    # align with tri3b models
    echo "$0: Starting exp/tri3b_ali"
    steps/align_fmllr.sh data/train data/lang exp/tri3b exp/tri3b_ali
fi

if [ $stage -le 20 ]; then
    # train and test chain models
    local/chain/run_tdnn.sh
fi
