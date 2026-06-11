#!/bin/bash
# $1 - File to Process (minus extension)
# $2 - Storage Location

mrom="$1"
filename="$2"
minlat="$3"
maxlat="$4"
startiloc="$5"
endiloc="$6"

# Convert mrom to lowercase once 
mrom=$(echo "$mrom" | tr '[:upper:]' '[:lower:]')

eval "$(~/miniforge3/bin/conda shell.bash hook)"
conda activate isis9.0.0

# Extract latitude and longitude from filename
lat=$(echo "$filename" | grep -o '[0-9]\{2\}[NS]')
lon=$(echo "$filename" | grep -o '[0-9]\{3\}[EW]')

# Convert longitude to numeric value (remove 'E' or 'W' and strip leading zeros)
lon_digits=$(echo "$lon" | grep -o '[0-9]\{3\}')
lon_number=$((10#$lon_digits))  # The 10# forces base 10 interpretation, avoiding octal

# Use sign convention if needed
if [[ "$lon" == *W ]]; then
    lon_value=$lon_number
else
    lon_value=$((-1 * lon_number))  # East as negative, if your coordinate system uses that
fi

# Compute minlon and maxlon
minlon=$(( (360-lon_value) - 9 ))
maxlon=$(( (360-lon_value) + 12 ))

echo "Latitude: $lat"
echo "Longitude: $lon_value"
echo "Min Longitude: $minlon"
echo "Max Longitude: $maxlon"

# Download the index.tab 
curl -O https://d32ky7zsovnyu5.cloudfront.net/MARCI/$mrom/index/index.tab 

# Search for the line containing the filename
line=$(grep "$filename" index.tab)

# Extract the date from the line (5th field in double quotes)
date=$(echo "$line" | awk -F',' '{gsub(/"/,""); print $5}')

# Extract only the year, month, and day (first 10 characters of the date)
utcDate=$(echo "$date" | cut -d'T' -f1)

# Print the filename and date
echo "Filename: $filename"
echo "Date: $utcDate"

outFileName="${mrom}_${filename}_${utcDate}"
outFileName="${filename}_${utcDate}_${minlat}to${maxlat}_${minlon}to${maxlon}"
echo $outFileName

if [ ! -f "$filename.IMG" ]; then
    echo "File not found. Downloading..."
    wget https://d32ky7zsovnyu5.cloudfront.net/MARCI/$mrom/data/$filename.IMG
else
    echo "File already exists. Skipping download."
fi

#MARCI IMG to Isis Cube - U03_072259_1475_MA_00N152W WORKS, also N14_067697_3425_MA_00N197W
marci2isis from=$filename.IMG to=$1.cub  flip=NO

# Generate the map templates - to get the strip we want only and wrapped at 180
maptemplate map=$1_marci_eq.map projection=equirectangular londom=360 clon=0 clat=0 targopt=user targetname=mars rngopt=user rngopt=user minlat=$minlat maxlat=$maxlat minlon=$minlon rngopt=user maxlon=$maxlon resopt=mpp resolution=500

# Update SPICE data for a camera cube WEB SHOULD BE YES
echo "Adding SPICE data"
echo "spiceinit from=$1.even.cub web=no cknadir=yes shape=ellipsoid" > add_spice
echo "spiceinit from=$1.odd.cub web=no cknadir=yes shape=ellipsoid" >> add_spice
parallel --jobs 2 < add_spice
rm add_spice

catlab from=$1.even.cub to=$1.proc.lbl

# Calibrate MARCI images
echo "Calibrating even and odd cubes" 
echo "marcical from=$1.even.cub to=$1.even.cal.cub" > calibrate_job
echo "marcical from=$1.odd.cub to=$1.odd.cal.cub" >> calibrate_job
parallel --jobs 2 < calibrate_job

# Remove intermediate files from import
rm calibrate_job
rm $1.even.cub
rm $1.odd.cub

catlab from=$1.even.cal.cub to=$1.proc.lbl append=true

# Now perform extra radiometric processing with custom python script
echo "Performing extra cleaning steps"
python marci_clean.py $1.even.cal.cub
python marci_clean.py $1.odd.cal.cub

#Trim pixels outside of phase, incidence, and emission angles
echo "Performing photometric trimming"
echo "photrim maxemission=75 maxincidence=100 from=$1.even.cal.cub to=$1.even.trim.cub" > trim_job
echo "photrim maxemission=75 maxincidence=100 from=$1.odd.cal.cub to=$1.odd.trim.cub" >> trim_job
parallel --jobs 2 < trim_job

#Remove intermediate files from calibration step
rm trim_job
rm $1.even.cal.cub
rm $1.odd.cal.cub

catlab from=$1.even.trim.cub to=$1.proc.lbl append=true

echo "Cropping images and separating to multiple cubes"
echo "crop from=$1.even.trim.cub+4 to=$1.even.red.cub" > crop_job
echo "crop from=$1.even.trim.cub+2 to=$1.even.green.cub" >> crop_job
echo "crop from=$1.even.trim.cub+1 to=$1.even.blue.cub" >> crop_job
echo "crop from=$1.odd.trim.cub+4 to=$1.odd.red.cub" >> crop_job
echo "crop from=$1.odd.trim.cub+2 to=$1.odd.green.cub" >> crop_job
echo "crop from=$1.odd.trim.cub+1 to=$1.odd.blue.cub" >> crop_job
parallel --jobs 6 < crop_job

#Remove intermediate files from trimming step
rm crop_job
rm $1.even.trim.cub
rm $1.odd.trim.cub

catlab from=$1.even.red.cub to=$1.proc.lbl append=true

# Map project equatorial region 
# Project images
echo "Map projecting images"
echo "cam2map from=$1.even.red.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.even.red.eq.cub" > project_job
echo "cam2map from=$1.odd.red.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.odd.red.eq.cub" >> project_job
echo "cam2map from=$1.even.green.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.even.green.eq.cub" >> project_job
echo "cam2map from=$1.odd.green.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.odd.green.eq.cub" >> project_job
echo "cam2map from=$1.even.blue.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.even.blue.eq.cub" >> project_job
echo "cam2map from=$1.odd.blue.cub map=$1_marci_eq.map pixres=map defaultrange=map trim=yes to=$1.odd.blue.eq.cub" >> project_job

parallel --jobs 6 < project_job

catlab from=$1.proc.lbl to=$1.proc.eq.lbl
catlab from=$1.even.red.eq.cub to=$1.proc.eq.lbl append=true

echo "Merging even-odd frames"
python marci_merge.py $1.even.red.eq.cub $1.odd.red.eq.cub $1.red.eq.cub
echo "Red cube merged"
python marci_merge.py $1.even.green.eq.cub $1.odd.green.eq.cub $1.green.eq.cub
echo "Green cube merged"
python marci_merge.py $1.even.blue.eq.cub $1.odd.blue.eq.cub $1.blue.eq.cub
echo "Blue cube merged"

#Remove intermediate map-projection files
rm project_job
rm $1.even.red.eq.cub
rm $1.odd.red.eq.cub
rm $1.even.green.eq.cub
rm $1.odd.green.eq.cub
rm $1.even.blue.eq.cub
rm $1.odd.blue.eq.cub

echo "reduce from=$1.red.eq.cub to=$1.red.eq.browse.cub mode=total ons=3600 onl=1800" > reduce_job
echo "reduce from=$1.green.eq.cub to=$1.green.eq.browse.cub mode=total ons=3600 onl=1800" >> reduce_job
echo "reduce from=$1.blue.eq.cub to=$1.blue.eq.browse.cub mode=total ons=3600 onl=1800" >> reduce_job
parallel --jobs 3 < reduce_job

rm reduce_job

#Export equatorial image to a RGB product
echo "Exporting products"

isis2std red=$1.red.eq.cub green=$1.green.eq.cub blue=$1.blue.eq.cub to=${mrom}_$outFileName.tif mode=rgb format=tiff bittype=u16bit compression=lzw minpercent=0.2 maxpercent=99.7

#Move files out of directory
mv $1_$outFilename.tif $2
mv $1.proc.eq.lbl $2

#Remove intermediate files from merging cubes
rm print.prt
rm ${mrom}_$outFileName.tfw
rm $1_marci_eq.map
rm $1.even.red.cub
rm $1.odd.red.cub
rm $1.even.blue.cub
rm $1.odd.blue.cub
rm $1.even.green.cub
rm $1.odd.green.cub
rm $1.even.trim.cub
rm $1.odd.trim.cub
rm $1.red.eq.cub
rm $1.green.eq.cub
rm $1.blue.eq.cub
rm $1.red.eq.browse.cub
rm $1.green.eq.browse.cub
rm $1.blue.eq.browse.cub
rm $1_RGB_eq.tfw
rm $1_RGB_eq.jgw 
rm $1.proc.lbl
rm $1.proc.eq.lbl
rm $2
rm $2.IMG

# Move all finished .tif files to /marci_raw (arrange by job)
dir="marci_raw_$5to$6"
mkdir -p "$dir"
mv *.tif "$dir"

exit 0