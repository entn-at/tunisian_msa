#!/bin/bash 

. ./cmd.sh
. ./path.sh
stage=0

. ./utils/parse_options.sh

set -e
set -o pipefail
set u

tmpdir=data/local/tmp
download_dir=$tmpdir/speech
tmp_tunis=$tmpdir/tunis
tmp_libyan=$tmpdir/libyan

data_dir=$download_dir/Tunisian_MSA/data
# location of test data 
libyan_src=$data_dir/speech/test/Libyan_MSA

# training data consists of 2 parts: answers and recordings (recited)
answers_transcripts=$data_dir/transcripts/train/answers.tsv
recordings_transcripts=$data_dir/transcripts/train/recordings.tsv

# location of test data
cls_rec_tr=$libyan_src/cls/data/transcripts/recordings/cls_recordings.tsv
lfi_rec_tr=$libyan_src/lfi/data/transcripts/recordings/lfi_recordings.tsv
srj_rec_tr=$libyan_src/srj/data/transcripts/recordings/srj_recordings.tsv
mbt_rec_tr=$data_dir/transcripts/test/mbt/recordings/mbt_recordings.tsv

if [ $stage -le 0 ]; then
    local/tamsa_download.sh
    fi

if [ $stage -le 1 ]; then
  # make acoustic model training  lists
  mkdir -p $tmp_tunis

  # get  wav file names

  # for recited speech
  # the data collection laptops had names like CTELLONE CTELLTWO ...
  for machine in CTELLONE CTELLTWO CTELLTHREE CTELLFOUR CTELLFIVE; do
      find $data_dir/speech/train/$machine \
	   -type f -name "*.wav" | grep Recordings | sort      >> \
							       $tmp_tunis/recordings_wav.txt
  done

  # get file names for Answers 
  for machine in CTELLONE CTELLTWO CTELLTHREE CTELLFOUR CTELLFIVE; do
	find $data_dir/speech/train/$machine -type f -name "*.wav" | grep Answers     | \
	    sort >> $tmp_tunis/answers_wav.txt
    done

    # make separate transcription lists for answers and recordings
    export LC_ALL=en_US.UTF-8
    local/answers_make_lists.pl $answers_transcripts

    utils/fix_data_dir.sh $tmp_tunis/answers

    local/recordings_make_lists.pl $recordings_transcripts

    utils/fix_data_dir.sh $tmp_tunis/recordings

    # consolidate lists
    # acoustic models will be trained on both recited and prompted speech
    mkdir -p $tmp_tunis/lists

    for x in wav.scp utt2spk text; do
	cat $tmp_tunis/answers/$x $tmp_tunis/recordings/$x | \
	    sort > $tmp_tunis/lists/$x
    done

    utils/fix_data_dir.sh $tmp_tunis/lists

    # get training lists
    mkdir -p data/train
    for x in wav.scp utt2spk text; do
	sort $tmp_tunis/lists/$x | tr "	" " " > data/train/$x
    done

    utils/utt2spk_to_spk2utt.pl data/train/utt2spk | sort > data/train/spk2utt

    utils/fix_data_dir.sh data/train

    # process the Libyan MSA data
    mkdir -p $tmp_libyan

    for s in cls lfi srj; do
	mkdir -p $tmp_libyan/$s

	# get list of  wav files
	find $libyan_src/$s -type f \
	     -name "*.wav" | grep recordings > $tmp_libyan/$s/recordings_wav.txt

	echo "$0: making recordings list for $s"
	local/test_recordings_make_lists.pl \
	    $libyan_src/$s/data/transcripts/recordings/${s}_recordings.tsv $s libyan
    done

    # process the Tunisian MSA test data

    mkdir -p $tmp_tunis/mbt

    # get list of  wav files
    find $data_dir/speech/test/mbt -type f \
	 -name "*.wav" | grep recordings > $tmp_tunis/mbt/recordings_wav.txt

    echo "$0: making recordings list for mbt"
    local/test_recordings_make_lists.pl \
	$data_dir/transcripts/test/mbt/recordings/mbt_recordings.tsv mbt tunis

    mkdir -p data/test
    # get the Libyan files
    for s in cls lfi srj; do
	for x in wav.scp utt2spk text; do
            cat     $tmp_libyan/$s/recordings/$x | tr "	" " " >> data/test/$x
	done
    done

    for x in wav.scp utt2spk text; do
	cat     $tmp_tunis/mbt/recordings/$x | tr "	" " " >> data/test/$x
    done

    utils/utt2spk_to_spk2utt.pl data/test/utt2spk | sort > data/test/spk2utt

    utils/fix_data_dir.sh data/test
fi

if [ $stage -le 2 ]; then
  local/qcri_lexicon_download.sh 

  local/qcri_buckwalter2utf8.pl > $tmpdir/dict/qcri_utf8.txt

  mkdir -p data/local/dict
fi

if [ $stage -le 3 ]; then
  # prepare a dictionary
    local/prepare_dict.sh data/local/tmp/dict/qcri_utf8.txt
fi

if [ $stage -le 4 ]; then
  # prepare the lang directory
  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/tmp/lang data/local/lang
fi

if [ $stage -le 5 ]; then
  # prepare lm on training and test transcripts
  local/prepare_lm.sh
fi

if [ $stage -le 5 ]; then
  utils/format_lm.sh \
    data/local/lang data/local/lm/lm_threegram.arpa.gz \
    data/local/dict/lexicon.txt data/lang
fi

if [ $stage -le 6 ]; then
    # extract acoustic features
    for fld in train test; do
        steps/make_plp_pitch.sh data/$fld exp/make_plp_pitch/$fld plp_pitch
        utils/fix_data_dir.sh data/$fld
        steps/compute_cmvn_stats.sh data/$fld exp/make_plp_pitchplp_pitch
        utils/fix_data_dir.sh data/$fld
    done
fi

if [ $stage -le 6 ]; then
    echo "$0: monophone training"
    steps/train_mono.sh  data/train data/lang exp/mono
fi

if [ $stage -le 7 ]; then
    # monophone evaluation
    (
        # make decoding graph for monophones
        utils/mkgraph.sh data/lang exp/mono exp/mono/graph

        # test monophones
        steps/decode.sh  exp/mono/graph data/test exp/mono/decode_test
    ) &
fi

if [ $stage -le 8 ]; then
    # align with monophones
    steps/align_si.sh  data/train data/lang exp/mono exp/mono_ali
fi

if [ $stage -le 9 ]; then
    echo "$0: Starting  triphone training in exp/tri1"
    steps/train_deltas.sh \
        --cluster-thresh 100 500 5000 data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 10 ]; then
    # test cd gmm hmm models
    # make decoding graphs for tri1
    (
        utils/mkgraph.sh data/lang exp/tri1 exp/tri1/graph

        # decode test data with tri1 models
        steps/decode.sh exp/tri1/graph data/test exp/tri1/decode_test
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
        utils/mkgraph.sh data/lang exp/tri2b exp/tri2b/graph

        # decode  test with tri2b models
        steps/decode.sh exp/tri2b/graph data/test exp/tri2b/decode_test
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
        utils/mkgraph.sh data/lang exp/tri3b exp/tri3b/graph

        # decode test sets with tri3b models
        steps/decode_fmllr.sh exp/tri3b/graph data/test exp/tri3b/decode_test
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
