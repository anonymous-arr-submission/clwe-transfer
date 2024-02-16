#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# TODO use getopts
# TODO make configdir relocatable
readonly configdir="$SCRIPT_DIR/config"
readonly config="${1:-default}"
source "$configdir/$config"

source "$SCRIPT_DIR"/functions/make-embeddings.sh
source "$SCRIPT_DIR"/functions/prepare-data.sh
source "$SCRIPT_DIR"/functions/build-vocab.sh
source "$SCRIPT_DIR"/functions/preprocess.sh
source "$SCRIPT_DIR"/functions/train.sh
source "$SCRIPT_DIR"/functions/evaluate.sh
source "$SCRIPT_DIR"/functions/backtranslate.sh

# TODO move all environment variables to config/vars
projectroot="${2:-$SCRIPT_DIR/saves}"
logdir="$projectroot"/logs
embeddingsdir="$projectroot"/embeddings
dictdir="$embeddingsdir"/dicts
datadir="$projectroot"/data
evaldir="$projectroot"/evaldata
data_in="$projectroot"/datasource

fasttext="$SCRIPT_DIR"/fastText
onmt="$SCRIPT_DIR"/onmt
moses="$SCRIPT_DIR"/mosesdecoder

get_latest_model() {
    local modeldir="$1"

    # output full model path
    echo -n "$modeldir/"
    ls -t "$modeldir" | head -1
}

set_stage() {
    stage="$1"

    savedir="$projectroot/saves.$stage"
    translationsdir="$savedir/translations/$model"

    mkdir -p "$savedir" "$translationsdir"
}

mkdir -p "$logdir"
mkdir -p "$embeddingsdir"
mkdir -p "$dictdir"
mkdir -p "$data_in"
mkdir -p "$datadir"
mkdir -p "$evaldir"



# Start basemodel stage
set_stage "base"

echo "Computing Cross-Linugal Word Embeddings..."
download_embeddings "${baselanguages[@]}"
compute_alignments "${clwepivot}" "${baselanguages[@]}"

echo "Downloading and building data..."
prepare_data
prepare_monolingual_data "${baselanguages[*]}" "${baselanguages[*]}"

echo "Building basesystem vocabulary..."
generate_specials "$embdim" "${baselanguages[@]}"
build_embeddings "${baselanguages[@]}"
build_basesystem_embeddings "${baselanguages[@]}"

echo "Concatenating training corpus..."
concat_data "$stage" "${baselanguages[*]}" "${baselanguages[*]}"

echo "Building PyTorch training shards and vocabulary..."
preprocess "$stage"

echo "Training basesystem..."
train "$stage" "$model" "$baseconfig"
basemodel="$(get_latest_model "$savedir/models/$model")"

echo "Evaluating base language BLEU scores..."
preprocess_evaluation_data "${baselanguages[*]}" "${baselanguages[*]}"
evauate_bleu "$stage" "$basemodel" "${baselanguages[*]}" "${baselanguages[*]}"



## Start new language stages
echo "Computing Cross-Linugal Word Embeddings for new languages..."
download_embeddings "${newlanguages[@]}"
compute_alignments "${clwepivot}" "${newlanguages[@]}"

echo "Preparing new language monolingual data..."
prepare_monolingual_data "${newlanguages[*]}" "${baselanguages[*]}"

echo "Building new language vocabularies..."
build_embeddings "${newlanguages[@]}"



# Start blind encoding stage
set_stage "blindenc"

echo "Evaluating blind encoding BLEU scores..."
prepare_evaluation_data "${newlanguages[*]}" "${baselanguages[*]}"
preprocess_evaluation_data "${newlanguages[*]}" "${baselanguages[*]}"
evauate_bleu "$stage" "$basemodel" "${newlanguages[*]}" "${baselanguages[*]}"



# Start blind decoding stage
set_stage "blinddec"

echo "Evaluating blind decoding BLEU scores..."
prepare_evaluation_data "${baselanguages[*]}" "${newlanguages[*]}"
preprocess_evaluation_data "${baselanguages[*]}" "${newlanguages[*]}"
evauate_bleu "$stage" "$basemodel" "${baselanguages[*]}" "${newlanguages[*]}"



# Start autoencoding stage
set_stage "autoencoder"

echo "Building autoencoder training corpus and vocabulary..."
build_newlang_vocab "$basemodel" "${newlanguages[*]}" "${newlanguages[*]}"
concat_autoencoding_corpus "$stage" "${newlanguages[*]}"
# TODO better solution for vocab path
preprocess_reuse_vocab "$stage" "$savedir/data.vocab.pt"

echo "Training autoencoder..."
train_continue "$stage" "$model" "$autoencoderconfig" "$basemodel"

echo "Evaluating autoencoding BLEU scores..."
aemodel="$(get_latest_model "$savedir/models/$model")"
evauate_bleu "$stage" "$aemodel" "${baselanguages[*]}" "${newlanguages[*]}"



# Start backtranslation stage
set_stage "backtranslate"
btmodel="$basemodel"

echo "Backtranslating monolingual data for new languages..."
prepare_backtranslation_data "$data_in" "${baselanguages[*]}" "${newlanguages[*]}"
freezeenc=y \
    backtranslation_round "$basemodel" "$btmodel" "${baselanguages[*]}" "${newlanguages[*]}"
btmodel="$(get_latest_model "$savedir/models/$model")"
evauate_bleu "$stage" "$btmodel" "${baselanguages[*]}" "${newlanguages[*]}"

prepare_backtranslation_data "$data_in" "${newlanguages[*]}" "${baselanguages[*]}"
freezeenc= \
    backtranslation_round "$basemodel" "$btmodel" "${newlanguages[*]}" "${baselanguages[*]}"
btmodel="$(get_latest_model "$savedir/models/$model")"
evauate_bleu "$stage" "$btmodel" "${newlanguages[*]}" "${baselanguages[*]}"


prepare_backtranslation_data "$data_in" "${baselanguages[*]}" "${newlanguages[*]}"
freezeenc=y \
    backtranslation_round "$basemodel" "$btmodel" "${baselanguages[*]}" "${newlanguages[*]}"
btmodel="$(get_latest_model "$savedir/models/$model")"
evauate_bleu "$stage" "$btmodel" "${baselanguages[*]}" "${newlanguages[*]}"

prepare_backtranslation_data "$data_in" "${newlanguages[*]}" "${baselanguages[*]}"
freezeenc= \
    backtranslation_round "$basemodel" "$btmodel" "${newlanguages[*]}" "${baselanguages[*]}"
btmodel="$(get_latest_model "$savedir/models/$model")"
evauate_bleu "$stage" "$btmodel" "${newlanguages[*]}" "${baselanguages[*]}"
