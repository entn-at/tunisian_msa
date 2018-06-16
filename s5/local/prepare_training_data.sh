#!/bin/bash -x

# Copyright 2018 John Morgan
# Apache 2.0.

d=$1
e=$2

# location of temporary working directories
tmp_dir=data/local/tmp
tmp_tunis=$tmp_dir/tunis

# training data consists of 2 parts: answers and recordings (recited)
answers_transcripts=$d/transcripts/answers.tsv
recordings_transcripts=$d/transcripts/recordings.tsv

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
    find $d/data/speech/$machine -type f -name "*.wav" | grep Answers     | \
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

