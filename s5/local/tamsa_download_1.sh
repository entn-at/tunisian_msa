#!/bin/bash -x

# The corpus is on openslr.org
speech=/mnt/disk01/tunisianmsa.tar.gz

tmpdir=data/local/tmp

# where to put the downloaded speech corpus
download_dir=$tmpdir/speech
data_dir=$download_dir/Tunisian_MSA/data

mkdir -p $download_dir

# download the corpus from openslr
if [ ! -f $download_dir/tamsa.tar.gz ]; then
  cp $speech  $download_dir/tamsa.tar.gz 

  (
    cd $download_dir
    tar -xzf tamsa.tar.gz
  )
fi
