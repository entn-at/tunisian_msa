#!/bin/bash

# The corpus is on openslr.org
speech="http://www.openslr.org/resources/46/Tunisian_MSA.tar.gz"

tmpdir=data/local/tmp

# where to put the downloaded speech corpus
download_dir=$tmpdir/speech
data_dir=$download_dir/Tunisian_MSA/data

mkdir -p $download_dir

# download the corpus from openslr
if [ ! -f $download_dir/tamsa.tar.gz ]; then
  wget -O $download_dir/tamsa.tar.gz $speech

  (
    cd $download_dir
    tar -xzf tamsa.tar.gz
  )
fi
