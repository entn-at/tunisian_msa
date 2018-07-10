#!/bin/bash

# Copyright 2018 John Morgan
# Apache 2.0.

# Begin configuration 
tmpdir=data/local/tmp
download_dir=$(pwd)
subs_src="http://opus.nlpl.eu/download.php?f=OpenSubtitles2018/mono/OpenSubtitles2018.ar.gz"
# End configuration

# download the subs corpus
if [ ! -f $download_dir/subs.txt.gz ]; then
    wget -O $download_dir/subs.txt.gz $subs_src
fi

if [ ! -f $download_dir/subs.txt ]; then
  (
    cd $download_dir
    gunzip subs.txt.gz
  )
  else
    echo "$0: subs file already downloaded."
fi
