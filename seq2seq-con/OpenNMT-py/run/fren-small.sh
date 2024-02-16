source activate gans
python -u train.py\
    -data ../kumarvon2018-data/fren/fren.prepared.opennmt.pt\
    -save_model saved_models/test\
    -layers 6\
    -rnn_size 512\
    -word_vec_size 512\
    -transformer_ff 1024\
    -heads 4\
    -warmup_init_lr 1e-8\
    -warmup_end_lr 0.0003\
    -min_lr 1e-9\
    -encoder_type transformer\
    -decoder_type transformer\
    -position_encoding\
    -train_steps 70000 \
    -max_generator_batches 2\
    -dropout 0.3\
    -batch_size 4000\
    -batch_type tokens\
    -normalization tokens \
    -accum_count 2\
    -optim adam\
    -adam_beta2 0.999\
    -decay_method linear\
    -weight_decay 0.0001\
    -warmup_steps 4000\
    -learning_rate 1\
    -max_grad_norm 25\
    -param_init 0 \
    -param_init_glorot\
    -label_smoothing 0.1\
    -valid_steps 10000\
    -save_checkpoint_steps 10000\
    -world_size 1\
    -gpu_ranks 0 > saved_models/test.out 2>&1 
