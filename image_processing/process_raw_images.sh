#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -lselect=1:ncpus=2:mem=16gb

eval "$(~/miniforge3/bin/conda shell.bash hook)"
source activate isis9.0.0
python process_raw_images.py
