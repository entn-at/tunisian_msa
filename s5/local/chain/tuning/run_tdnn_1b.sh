#!/bin/bash

set -euo pipefail

stage=0
decode_nj=10
train_set=train
test_sets="test"
gmm=tri3b
nnet3_affix=

affix=1b
tree_affix=
train_stage=-10
get_egs_stage=-10
decode_iter=

# training options
# training chunk-options
chunk_width=140,100,160
chunk_left_context=0
chunk_right_context=0
common_egs_dir=
xent_regularize=0.1

srand=0
remove_egs=true
reporting_email=

#decode options
test_online_decoding=true  # if true, it will run the last decoding stage.

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali
tree_dir=exp/chain${nnet3_affix}/tree${tree_affix:+_$tree_affix}
lang=data/lang_chain
lat_dir=exp/chain${nnet3_affix}/${gmm}_${train_set}_lats
dir=exp/chain${nnet3_affix}/tdnn${affix}
train_data_dir=data/${train_set}
lores_train_data_dir=data/${train_set}

for f in $gmm_dir/final.mdl $train_data_dir/feats.scp \
    $lores_train_data_dir/feats.scp $ali_dir/ali.1.gz; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
done

if [ $stage -le 10 ]; then
  echo "$0: creating lang directory $lang with chain-type topology"
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  if [ -d $lang ]; then
    if [ $lang/L.fst -nt data/lang/L.fst ]; then
      echo "$0: $lang already exists, not overwriting it; continuing"
    else
      echo "$0: $lang already exists and seems to be older than data/lang..."
      echo " ... not sure what to do.  Exiting."
      exit 1;
    fi
  else
    cp -r data/lang $lang
    silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
    nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
    # Use our special topology... note that later on may have to tune this
    # topology.
    steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
  fi
fi

if [ $stage -le 11 ]; then
    # Get the alignments as lattices (gives the chain training more freedom).
    # use the same num-jobs as the alignments
    steps/align_fmllr_lats.sh \
	--nj 75 --cmd "$train_cmd" ${lores_train_data_dir} data/lang $gmm_dir \
	$lat_dir
    rm $lat_dir/fsts.*.gz # save space
fi

if [ $stage -le 12 ]; then
  # Build a tree using our new topology.  We know we have alignments for the
  # speed-perturbed data (local/nnet3/run_ivector_common.sh made them), so use
  # those.  The num-leaves is always somewhat less than the num-leaves from
  # the GMM baseline.
   if [ -f $tree_dir/final.mdl ]; then
     echo "$0: $tree_dir/final.mdl already exists, refusing to overwrite it."
     exit 1;
  fi
  steps/nnet3/chain/build_tree.sh \
    --frame-subsampling-factor 3 \
    --context-opts "--context-width=2 --central-position=1" \
    --cmd "$train_cmd" \
    3500 \
    ${lores_train_data_dir} \
    $lang $ali_dir $tree_dir
fi


if [ $stage -le 13 ]; then
  mkdir -p $dir
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $tree_dir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print 0.5/$xent_regularize" | python)

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1,2,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 dim=512
  relu-batchnorm-layer name=tdnn2 dim=512 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn3 dim=512 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn4 dim=512 input=Append(-3,0,3)
  relu-batchnorm-layer name=tdnn5 dim=512 input=Append(-3,0,3)
  relu-batchnorm-layer name=tdnn6 dim=512 input=Append(-6,-3,0)

  ## adding the layers for chain branch
  relu-batchnorm-layer name=prefinal-chain dim=512 target-rms=0.5
  output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5

  # adding the layers for xent branch
  # This block prints the configs for a separate output that will be
  # trained with a cross-entropy objective in the 'chain' models... this
  # has the effect of regularizing the hidden parts of the model.  we use
  # 0.5 / args.xent_regularize as the learning rate factor- the factor of
  # 0.5 / args.xent_regularize is suitable as it means the xent
  # final-layer learns at a rate independent of the regularization
  # constant; and the 0.5 was tuned so as to make the relative progress
  # similar in the xent and regular final layers.
  relu-batchnorm-layer name=prefinal-xent input=tdnn6 dim=512 target-rms=0.5
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi


if [ $stage -le 14 ]; then
  steps/nnet3/chain/train.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.online-ivector-dir=$train_ivector_dir \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient=0.1 \
    --chain.l2-regularize=0.00005 \
    --chain.apply-deriv-weights=false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.srand=$srand \
    --trainer.max-param-change=2.0 \
    --trainer.num-epochs=10 \
    --trainer.frames-per-iter=3000000 \
    --trainer.optimization.num-jobs-initial=1 \
    --trainer.optimization.num-jobs-final=1 \
    --trainer.optimization.initial-effective-lrate=0.001 \
    --trainer.optimization.final-effective-lrate=0.0001 \
    --trainer.optimization.shrink-value=1.0 \
    --trainer.optimization.proportional-shrink=150.0 \
    --trainer.num-chunk-per-minibatch=256,128,64 \
    --trainer.optimization.momentum=0.0 \
    --egs.chunk-width=$chunk_width \
    --egs.chunk-left-context=$chunk_left_context \
    --egs.chunk-right-context=$chunk_right_context \
    --egs.chunk-left-context-initial=0 \
    --egs.chunk-right-context-final=0 \
    --egs.dir="$common_egs_dir" \
    --egs.opts="--frames-overlap-per-eg 0" \
    --cleanup.remove-egs=$remove_egs \
    --use-gpu=true \
    --reporting.email="$reporting_email" \
    --feat-dir=$train_data_dir \
    --tree-dir=$tree_dir \
    --lat-dir=$lat_dir \
    --dir=$dir  || exit 1;
fi

if [ $stage -le 15 ]; then
    # Note: it's not important to give mkgraph.sh the lang directory with the
    # matched topology (since it gets the topology file from the model).
	utils/mkgraph.sh \
	    --self-loop-scale 1.0 \
	    data/lang_test \
	    $tree_dir \
	    $tree_dir/graph || exit 1;
fi

if [ $stage -le 16 ]; then
    frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
    rm $dir/.error 2>/dev/null || true

    for data in $test_sets; do
	(
	    nspk=$(wc -l <data/${data}/spk2utt)
	    steps/nnet3/decode.sh \
		--acwt 1.0 \
		--post-decode-acwt 10.0 \
		--extra-left-context $chunk_left_context \
		--extra-right-context $chunk_right_context \
		--extra-left-context-initial 0 \
		--extra-right-context-final 0 \
		--frames-per-chunk $frames_per_chunk \
		--nj $nspk \
		--cmd "$decode_cmd" \
		--num-threads 4 \
		--online-ivector-dir "" \
		$tree_dir/graph \
		data/${data} \
		    ${dir}/decode_${data} || exit 1;
	) || touch $dir/.error &
    done
    wait
    [ -f $dir/.error ] && echo "$0: there was a problem while decoding" && exit 1
fi

# Not testing the 'looped' decoding separately, because for
# TDNN systems it would give exactly the same results as the
# normal decoding.

if $test_online_decoding && [ $stage -le 17 ]; then
    # note: if the features change (e.g. you add pitch features), you will have to
    # change the options of the following command line.
    steps/online/nnet3/prepare_online_decoding.sh \
	--mfcc-config conf/mfcc.conf \
	$lang \
	exp/nnet3${nnet3_affix}/extractor \
	${dir} \
	${dir}_online

    rm $dir/.error 2>/dev/null || true

    for data in $test_sets; do
	(
	    nspk=$(wc -l <data/${data}/spk2utt)
	    # note: we just give it "data/${data}" as it only uses the wav.scp, the
	    # feature type does not matter.
	    steps/online/nnet3/decode.sh \
		--acwt 1.0 \
		--post-decode-acwt 10.0 \
		--nj $nspk \
		--cmd "$decode_cmd" \
		$tree_dir/graph \
		data/${data} \
		${dir}_online/decode_${data} || exit 1
	) || touch $dir/.error &
    done
    wait
    [ -f $dir/.error ] && echo "$0: there was a problem while decoding" && exit 1
fi

exit 0;
