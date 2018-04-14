#!/bin/bash 

. ./cmd.sh
. ./path.sh
stage=0

. ./utils/parse_options.sh

set -e
set -o pipefail
set u

tmpdir=data/local/tmp
#   data is on openslr.org
speech="http://www.openslr.org/resources/46/Tunisian_MSA.tar.gz"
lex=http://alt.qcri.org/resources/speech/dictionary/ar-ar_lexicon_2014-03-17.txt.bz2

# where to put the downloaded speech corpus
speech_download_dir=$tmpdir/speech
lex_download_dir=$tmpdir/lex
speech_data_dir=$speech_download_dir/Tunisian_MSA/data

# location of test data 
libyan_src=/mnt/disk01/Libyan_MSA

if [ $stage -le 0 ]; then
    mkdir -p $tmpdir/speech
    # download the speech corpus from openslr
    if [ ! -f $speech_download_dir/Tunisian_MSA.tar.gz ]; then
	wget -O $speech_download_dir/Tunisian_MSA.tar.gz $speech

	(
	    #run in shell, so we don't have to remember the path
	    cd $speech_download_dir
	    tar -xzf Tunisian_MSA.tar.gz
	)
	local/prepare_data.sh $speech_data_dir $libyan_src
    else
local/prepare_data.sh $speech_data_dir $libyan_src
    fi
fi

if [ $stage -le 1 ]; then
    # prepare a dictionary
    mkdir -p $lex_download_dir
    # download the dictionary 
    if [ ! -f $lex_download_dir/qcri.bz2 ]; then
	wget -O $lex_download_dir/qcri.bz2 $lex

	(
	    cd $lex_download_dir
	    bunzip2 qcri.bz2
	)
	local/prepare_dict.sh $lex_download_dir/qcri
    else
	(
	    cd $lex_download_dir
	    bunzip2 qcri.bz2
	    )
	local/prepare_dict.sh $lex_download_dir/qcri
    fi
fi

if [ $stage -le 2 ]; then
    # prepare the lang directory
    utils/prepare_lang.sh data/local/dict "<UNK>" data/local/tmp/lang data/local/lang
fi

if [ $stage -le 3 ]; then
    # prepare lm on training and test transcripts
    local/prepare_lm.sh
fi

if [ $stage -le 4 ]; then
    utils/format_lm.sh \
        data/local/lang data/local/lm/lm_threegram.arpa.gz \
        data/local/dict/lexicon.txt data/lang
fi

if [ $stage -le 6 ]; then
    # extract acoustic features
    mkdir -p exp

    for fld in train test; do
        if [ -e data/$fld/cmvn.scp ]; then
            rm data/$fld/cmvn.scp
        fi

        steps/make_plp_pitch.sh \
            --cmd "$train_cmd" --nj 10 data/$fld exp/make_plp_pitch/$fld \
            plp_pitch

        utils/fix_data_dir.sh data/$fld

        steps/compute_cmvn_stats.sh data/$fld exp/make_plp_pitchplp_pitch

        utils/fix_data_dir.sh data/$fld
    done
fi
exit
if [ $stage -le 7 ]; then
    echo "$0: monophone training"
    steps/train_mono.sh --nj 10 --cmd "$train_cmd" data/train data/lang exp/mono
fi

if [ $stage -le 8 ]; then
    # monophone evaluation
    (
        # make decoding graph for monophones
        utils/mkgraph.sh data/lang_test exp/mono exp/mono/graph

        # test monophones
        steps/decode.sh --nj 4  exp/mono/graph data/test exp/mono/decode_test
    ) &
fi

if [ $stage -le 9 ]; then
    # align with monophones
    steps/align_si.sh \
        --nj 10 --cmd "$train_cmd" data/train data/lang exp/mono exp/mono_ali
fi

if [ $stage -le 10 ]; then
    echo "$0: Starting  triphone training in exp/tri1"
    steps/train_deltas.sh \
        --cmd "$train_cmd" --cluster-thresh 100 500 5000 data/train data/lang \
	exp/mono_ali exp/tri1
fi

if [ $stage -le 11 ]; then
    # test cd gmm hmm models
    # make decoding graphs for tri1
    (
        utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph

        # decode test data with tri1 models
        steps/decode.sh --nj 4 exp/tri1/graph data/test exp/tri1/decode_test
    ) &
fi

if [ $stage -le 12 ]; then
    # align with triphones
    steps/align_si.sh \
        --nj 10 --cmd "$train_cmd" data/train data/lang exp/tri1 exp/tri1_ali
fi

if [ $stage -le 13 ]; then
    echo "$0: Starting (lda_mllt) triphone training in exp/tri2b"
    steps/train_lda_mllt.sh \
        --splice-opts "--left-context=3 --right-context=3" 700 8000 \
        data/train data/lang exp/tri1_ali exp/tri2b
fi

if [ $stage -le 14 ]; then
    (
        #  make decoding FSTs for tri2b models
        utils/mkgraph.sh data/lang_test exp/tri2b exp/tri2b/graph

        # decode  test with tri2b models
        steps/decode.sh --nj 4  exp/tri2b/graph data/test exp/tri2b/decode_test
    ) &
fi

if [ $stage -le 15 ]; then
    # align with lda and mllt adapted triphones
    steps/align_si.sh \
        --use-graphs true --nj 10 --cmd "$train_cmd" data/train data/lang \
        exp/tri2b exp/tri2b_ali
fi

if [ $stage -le 16 ]; then
    echo "$0: Starting (SAT) triphone training in exp/tri3b"
    steps/train_sat.sh \
        --cmd "$train_cmd" 800 10000 data/train data/lang exp/tri2b_ali \
        exp/tri3b
fi

if [ $stage -le 17 ]; then
    (
        # make decoding graphs for SAT models
        utils/mkgraph.sh data/lang_test exp/tri3b exp/tri3b/graph

        # decode test sets with tri3b models
        steps/decode_fmllr.sh \
            --nj 4 --cmd "$decode_cmd" exp/tri3b/graph data/test \
            exp/tri3b/decode_test
    ) &
fi

if [ $stage -le 18 ]; then
    # align with tri3b models
    echo "$0: Starting exp/tri3b_ali"
    steps/align_fmllr.sh \
        --nj 10 --cmd "$train_cmd" data/train data/lang exp/tri3b exp/tri3b_ali
fi

if [ $stage -le 20 ]; then
    # train and test chain models
    local/chain/run_tdnn.sh
fi
