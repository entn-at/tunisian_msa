#!/bin/bash  

# Copyright 2018 John Morgan
# Apache 2.0.

# configuration variables
tmpdir=data/local/tmp
download_dir=$(pwd)
tmp_tunis=$tmpdir/tunis
tmp_libyan=$tmpdir/libyan
data_dir=$download_dir/Tunisian_MSA/data
# location of test data 
libyan_src=$data_dir/speech/test/Libyan_MSA
libyan_arl_data=$(pwd)/Libyan_MSA_ARL

# end of configuration variable settings

# process the Libyan MSA dev answers data
# get list of  answers wav files
for s in adel anwar bubaker hisham mukhtar redha yousef; do
    echo "$0: looking for wav files for $s answers."
    mkdir -p $tmp_libyan/answers/$s
    find \
	$libyan_arl_data/$s/data/speech -type f \
	-name "*.wav" \
	| grep answers > $tmp_libyan/answers/$s/wav.txt

    local/dev_answers_make_lists.pl \
	$libyan_arl_data/$s/data/transcripts/answers/${s}_answers.tsv $s libyan
done

# process the Libyan MSA dev recited data

# get list of  wav files
for s in adel anwar bubaker hisham mukhtar redha yousef; do
    echo "$0: looking for recited wav files for $s."
    mkdir -p $tmp_libyan/recordings/$s
    find \
	$libyan_arl_data/$s/data/speech -type f \
	-name "*.wav" | grep recordings > $tmp_libyan/recordings/$s/wav.txt

    local/dev_recordings_make_lists.pl \
	$libyan_arl_data/$s/data/transcripts/recordings/${s}_recordings.tsv $s libyan
done

# consolidate both recited and answers as dev data 
mkdir -p data/dev

for m in answers recordings; do
    for s in adel anwar bubaker hisham mukhtar redha yousef; do
	for x in wav.scp utt2spk text; do
	    cat     $tmp_libyan/$m/$s/$x | tr "	" " " >> data/dev/$x
	done
    done
done

utils/utt2spk_to_spk2utt.pl data/dev/utt2spk | sort > data/dev/spk2utt

utils/fix_data_dir.sh data/dev
