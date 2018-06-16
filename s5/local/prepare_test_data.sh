#!/bin/bash -x

# Copyright 2018 John Morgan
# Apache 2.0.

e=$2

# location of temporary working directories
tmp_dir=data/local/tmp
tmp_tunis=$tmp_dir/tunis
tmp_libyan=$tmp_dir/libyan

# location of test data
cls_rec_tr=$e/cls/data/transcripts/recordings/cls_recordings.tsv
lfi_rec_tr=$e/lfi/data/transcripts/recordings/lfi_recordings.tsv
srj_rec_tr=$e/srj/data/transcripts/recordings/srj_recordings.tsv
mbt_rec_tr=$d/mbt/data/transcripts/recordings/mbt_recordings.tsv

# make acoustic model training  lists
mkdir -p $tmp_tunis

mkdir -p $tmp_tunis/lists

# process the Libyan MSA data
mkdir -p $tmp_libyan

for s in cls lfi srj; do
    mkdir -p data/local/tmp/libyan/$s

    # get list of  wav files
    find $e/$s -type f \
	 -name "*.wav" | grep recordings > $tmp_libyan/$s/recordings_wav.txt

    echo "$0: making recordings list for $s"
    local/test_recordings_make_lists.pl \
	$e/$s/data/transcripts/recordings/${s}_recordings.tsv $s libyan
done

# process the Tunisian MSA test data

mkdir -p data/local/tmp/tunis/mbt

    # get list of  wav files
    find $d/mbt -type f \
	 -name "*.wav" | grep recordings > $tmp_tunis/mbt/recordings_wav.txt

    echo "$0: making recordings list for mbt"
    local/test_recordings_make_lists.pl \
	$d/mbt/data/transcripts/recordings/mbt_recordings.tsv mbt tunis

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
