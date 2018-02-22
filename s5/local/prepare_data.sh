#!/bin/bash

# Copyright 2018 John Morgan
# Apache 2.0.

d=$1
e=$2

# location of temporary working directories
tmp_dir=data/local/tmp
tmp_tunis=$tmp_dir/tunis
tmp_libyan=$tmp_dir/libyan

# training data consists of 2 parts: answers and recordings (recited)
answers_transcripts=$d/transcripts/answers.tsv
recordings_transcripts=$d/transcripts/recordings.tsv

# location of test data
cls_rec_tr=$e/cls/data/transcripts/recordings/cls_recordings.tsv
lfi_rec_tr=$e/lfi/data/transcripts/recordings/lfi_recordings.tsv
srj_rec_tr=$e/srj/data/transcripts/recordings/srj_recordings.tsv

# make acoustic model training  lists
mkdir -p $tmp_tunis

# get  wav file names

# for recited speech
# the data collection laptops had names like CTELLONE CTELLTWO ...
for machine in CTELLONE CTELLTWO CTELLTHREE CTELLFOUR CTELLFIVE; do
    find $d/speech/$machine -type f -name "*.wav" | grep Recordings | \
	sort      >> $tmp_tunis/recordings_wav.txt
done

# get file names for Answers 
for machine in CTELLFIVE CTELLFOUR CTELLONE CTELLTHREE CTELLTWO; do
    find $d/speech/$machine -type f -name "*.wav" | grep Answers     | \
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
    mkdir -p data/local/tmp/libyan/$s

    # get list of  wav files
    find $e/$s -type f \
	 -name "*.wav" | grep recordings > $tmp_libyan/$s/recordings_wav.txt

    echo "$0: making recordings list for $s"
    local/libyan_recordings_make_lists.pl \
	$e/$s/data/transcripts/recordings/${s}_recordings.tsv $s
done


mkdir -p data/test
# get the Libyan files
for s in cls lfi srj; do
    for x in wav.scp utt2spk text; do
        cat     $tmp_libyan/$s/recordings/$x | tr "	" " " >> data/test/$x
    done
done

utils/utt2spk_to_spk2utt.pl data/test/utt2spk | sort > data/test/spk2utt

utils/fix_data_dir.sh data/test