#!/bin/bash

# Copyright 2018 John Morgan
# Apache 2.0.

# The corpus is on openslr.org
speech="http://www.openslr.org/resources/46/Tunisian_MSA.tar.gz"

# where to put the downloaded speech corpus
download_dir=$(pwd)
data_dir=$download_dir/Tunisian_MSA/data

# download the corpus from openslr
if [ ! -f $download_dir/tamsa.tar.gz ]; then
  wget -O $download_dir/tamsa.tar.gz $speech

  (
    cd $download_dir
    tar -xzf tamsa.tar.gz
  )
fi
