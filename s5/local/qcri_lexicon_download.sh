#!/bin/bash 

lex="http://alt.qcri.org/resources/speech/dictionary/ar-ar_lexicon_2014-03-17.txt.bz2"

tmpdir=data/local/tmp

# where to put the downloaded speech corpus
download_dir=$tmpdir/dict

mkdir -p $download_dir

# download the corpus 
if [ ! -f $download_dir/qcri.txt.bz2 ]; then
  wget -O $download_dir/qcri.txt.bz2 $lex

  (
    cd $download_dir
    bunzip2 -d qcri.txt.bz2
  )
fi
